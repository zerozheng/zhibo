//
//  RTMPSession.swift
//  zhiboApp
//
//  Created by zero on 17/2/23.
//  Copyright © 2017年 zero. All rights reserved.
//

import Foundation

public struct RTMPStatus: OptionSet {
    
    public var rawValue: UInt32
    
    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
    
    static var unconnect            = { return RTMPStatus(rawValue: 1) }() //1
    static var connected            = { return RTMPStatus(rawValue: 1 << 1) }() //2
    static var handshakeStarted     = { return RTMPStatus(rawValue: 1 << 2) }() //4
    static var handshakeC0          = { return RTMPStatus(rawValue: 1 << 3) }() //8
    static var handshakeC1          = { return RTMPStatus(rawValue: 1 << 4) }() //16
    static var handshakeS0          = { return RTMPStatus(rawValue: 1 << 5) }() //32
    static var handshakeS1          = { return RTMPStatus(rawValue: 1 << 6) }() //64
    static var handshakeS2          = { return RTMPStatus(rawValue: 1 << 7) }() //128
    static var handshakeC2          = { return RTMPStatus(rawValue: 1 << 8) }() //256
    static var handshakeComplete    = { return RTMPStatus(rawValue: 1 << 9) }() //512
    static var fcPublish            = { return RTMPStatus(rawValue: 1 << 10) }()
    static var ready                = { return RTMPStatus(rawValue: 1 << 11) }()
    static var start                = { return RTMPStatus(rawValue: 1 << 12) }()
    static var error                = { return RTMPStatus(rawValue: 1 << 13) }()
    static var disconnected         = { return RTMPStatus(rawValue: 1 << 14) }()
}

protocol RTMPSessionDelegate: NSObjectProtocol {
    func rtmpSession(session: RTMPSession, didChangeStatus status: RTMPStatus)
}

let RTMPWriteQueue: String = "com.oralCare.RTMPWriteQueue"

class RTMPSession: NSObject {
    
    weak var delegate: RTMPSessionDelegate?
    
    lazy var streamSession: StreamSession = StreamSession(delegate: self)
    
    fileprivate(set) var status: RTMPStatus {
        didSet{
            self.delegate?.rtmpSession(session: self, didChangeStatus: status)
        }
    }
    
    init(delegate: RTMPSessionDelegate? = nil) {
        self.status = RTMPStatus.unconnect
        self.writeSemaphore = DispatchSemaphore(value: 0)
        self.writeQueue = DispatchQueue(label: RTMPWriteQueue)
        self.delegate = delegate
        self.streamInBuffer = RingBuffer(capacity: RTMPBufferSize)
        self.stop = false
        self.maxCongestionSize = 1024*1024*10
        self.bufferSize = 0
        self.shouldClearCongestionBuffer = false
        super.init()
    }
    
    deinit {
        stop = true
    }
    
    
    // 推流链接
    fileprivate var urlString: String?
    
    /* 以下属性是为了 写入/读出数据 而引入的 */
    fileprivate var writeSemaphore: DispatchSemaphore //写入信号
    fileprivate var writeQueue: DispatchQueue //写入队列，串行异步
    fileprivate var streamInBuffer: RingBuffer //用于读取握手数据
    fileprivate var s1: UnsafeMutablePointer<UInt8>? //存储握手s1数据,方便c2使用
    fileprivate var byteRateManager: ByteRateManager? //码率的传输信息
    fileprivate var stop: Bool //是否停止写入
    
    /* 以下属性是为了解决拥塞控制而引入的 */
    fileprivate var maxCongestionSize: Int //最大拥塞数, 默认10m
    fileprivate var bufferSize: Int //需要发送的数据总大小
    fileprivate var bufferSizeLock: NSLock = NSLock() //互斥锁,解决bufferSize设置的问题
    fileprivate var clearDate: Date? //为重置session而引入的,用于记录重置的时间. session重置时,所有早于clearDate的bufferSize都将不起作用
    fileprivate var shouldClearCongestionBuffer: Bool //如果发生拥塞，且拥塞数超过了maxCongestionSize, 而且该帧视频数据是关键帧，则为true. 表示可以丢弃数据
    fileprivate var clearCongestionBufferDate: Date? //如果视频数据是关键帧,则记录该时间，早于该帧的数据将会被丢弃
}

// MARK: public variable and method
extension RTMPSession {
    func connect(withUrlString urlString: String) {
        if self.status.subtracting([.unconnect, .disconnected]).rawValue > 0 {
            reset()
        }
        
        guard let scheme = urlString.scheme, let host = urlString.host else {
            debugPrint("所传的urlString的scheme或者host不能为nil")
            return
        }
        
        if scheme.lowercased() != RTMPScheme {
            debugPrint("所传的urlString的scheme不是rtmp")
            return
        }
        
        self.urlString = urlString
        streamSession.connect(host: host, port: urlString.port ?? RTMPDefaultPort)
    }
    
    func detectByteRate(withCallback callback: ByteRateCallback?) {
        byteRateManager = ByteRateManager()
        byteRateManager!.callback = callback
        byteRateManager!.start()
    }
    
}

// MARK: Private variable and method
extension RTMPSession {
    func reset() {
        status = .unconnect
        urlString = nil
        streamInBuffer.clear()
        s1 = nil
        byteRateManager?.clear()
        bufferSize = 0
        clearDate = Date()
    }
    
    
    func increase(size: Int, date: Date = Date()) {
        
        if clearDate != nil && clearDate! > date {
            return
        }
        bufferSizeLock.lock()
        bufferSize += size
        bufferSizeLock.unlock()
    }
    
    func write(data: UnsafePointer<UInt8>, size: Int, iskeyFrame: Bool = false, date: Date = Date()) {
        
        guard size > 0 else { return }
        increase(size: size)
        byteRateManager?.willSendBuffer(size: bufferSize)
        shouldClearCongestionBuffer = self.bufferSize >= self.maxCongestionSize && iskeyFrame
        if iskeyFrame { clearCongestionBufferDate = date }
        
        writeQueue.async {
            let buf: UnsafeMutablePointer<UInt8> = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
            buf.assign(from: data, count: size)
            
            var totalSent = 0
            while size - totalSent > 0 && !self.stop {
                
                if self.shouldClearCongestionBuffer && date != self.clearCongestionBufferDate {
                    self.byteRateManager?.didSentBuffer(size: 0)
                    self.increase(size: -(size - totalSent))
                    self.byteRateManager?.willSendBuffer(size: self.bufferSize)
                    break
                }else{
                    let sent = self.streamSession.write(from: &buf[totalSent], size: size - totalSent)
                    totalSent += sent
                    self.byteRateManager?.didSentBuffer(size: sent)
                    self.increase(size: -sent)
                    self.byteRateManager?.willSendBuffer(size: self.bufferSize)
                    if sent == 0  && size - totalSent > 0{
                        let _ = self.writeSemaphore.wait(timeout: DispatchTime.now()+1)
                    }
                }
            }
        }
    }
    
    
    func dataReceived() {
        
        var buffer: UnsafeMutablePointer<UInt8> = UnsafeMutablePointer<UInt8>.allocate(capacity: RTMPBufferSize)
        buffer.initialize(to: 0)
        
        defer {
            buffer.deinitialize()
            buffer.deallocate(capacity: RTMPBufferSize)
        }
        
        var stop = false
        repeat {
            let maxUsableLength = streamInBuffer.maxSpacesAvailable()
            let readlength = streamSession.read(to: buffer, size: maxUsableLength)
            let _ = streamInBuffer.put(data: buffer, size: readlength)
            var needMoreDataForSignature = false
            while streamInBuffer.maxBytesAvailable() > 0 && !needMoreDataForSignature {
                if status.contains(.handshakeS0) {
                    var s0: UInt8 = 0
                    let _ = streamInBuffer.get(buffer: &s0, size: 1)
                    if s0 == 0x03 {
                        status.remove(.handshakeS0)
                    }else{
                        debugPrint("rtmp版本不是03的")
                    }
                }else if status.contains(.handshakeS1){
                    if streamInBuffer.maxBytesAvailable() >= RTMPSignatureSize {
                        let signature: UnsafeMutablePointer<UInt8> = UnsafeMutablePointer<UInt8>.allocate(capacity: RTMPSignatureSize)
                        let _ = streamInBuffer.get(buffer: signature, size: RTMPSignatureSize)
                        s1 = signature
                        status.remove(.handshakeS1)
                        handshake()
                    }else{
                        needMoreDataForSignature = true
                    }
                }else if status.contains(.handshakeS2){
                    if streamInBuffer.maxBytesAvailable() >= RTMPSignatureSize {
                        /**
                         * 如果有需要，可以判断此握手s2返回的随机数是否等于握手c1的随机数
                         
                            var signature: UnsafeMutablePointer<UInt8> = UnsafeMutablePointer<UInt8>.allocate(capacity: RTMPSignatureSize)
                            let _ = streamInBuffer.get(buffer: signature, size: RTMPSignatureSize)
                         */
                        status.remove(.handshakeS2)
                        handshake()
                        sendConnectPacket()
                    }else{
                        needMoreDataForSignature = true
                    }
                }else{
                    if !parseCurrentData() {
                        needMoreDataForSignature = true
                        stop = true
                    }
                }
            }
        }while (streamSession.status.contains(.hasBytesAvailable) && !stop)
    }
    
    // MARK: handshake About
    func handshake() {
        
        guard status.rawValue > RTMPStatus.handshakeStarted.rawValue, status.rawValue < RTMPStatus.handshakeComplete.rawValue else {return}
        
        if status.contains(.handshakeC0) {
            handshakeSendC0()
        }else if status.contains(.handshakeC1){
            handshakeSendC1()
        }else if status.contains(.handshakeC2) && !status.contains(.handshakeS2) {
            handshakeSendC2()
        }
    }
    
    func handshakeSendC0() {
        var c0: UInt8 = 0x03
        write(data: &c0, size: 1)
        status.remove(.handshakeC0)
        handshake();
    }
    
    func handshakeSendC1() {
        
        let c1 = UnsafeMutablePointer<UInt8>.allocate(capacity: RTMPSignatureSize)
        let timeAndZero: UInt8 = 0x00
        let timeAndZeroSize: Int = 8
        c1.initialize(to: timeAndZero, count: timeAndZeroSize)
        c1.advanced(by: timeAndZeroSize).assign(from: RandomData.generateRandomData(withSize: UInt(RTMPSignatureSize-timeAndZeroSize)), count: RTMPSignatureSize-timeAndZeroSize)
        
        write(data: c1, size: RTMPSignatureSize)
        status.remove(.handshakeC1)
    }
    
    func handshakeSendC2() {
        
        let c2 = UnsafeMutablePointer<UInt8>.allocate(capacity: RTMPSignatureSize)
        guard s1 != nil else {
            debugPrint("rtmp握手s1数据为nil")
            return
        }
        c2.assign(from: s1!, count: RTMPSignatureSize)
        
        var zero: UInt8 = 0x00
        let zeroSize: Int = 4
        let timeSize: Int = 4
        c2.advanced(by: timeSize).assign(from: &zero, count: zeroSize)
        write(data: c2, size: RTMPSignatureSize)
        
        status = .handshakeComplete
        
        s1!.deallocate(capacity: RTMPSignatureSize)
        s1 = nil
    }
    

    func sendConnectPacket() {
        
        guard let url = self.urlString else {
            print("connectUrl 为nil")
            return
        }
        
        var connectUrl: String = ""
        
        do {
            try connectUrl = url.rtmpLink()
        }catch {
            if error is RTMPError {
                print((error as! RTMPError).errorDescription)
            }else{
                print("unknown error happen")
            }
            return
        }
        
        let commandObject: [String: AFM0Encoder] = [CCOName.app.rawValue: url.app ?? "", CCOName.tcUrl.rawValue: connectUrl, CCOName.fpad.rawValue: false, CCOName.audioCodecs.rawValue: 10.0, CCOName.videoCodecs.rawValue: 7.0, CCOName.videoFunction.rawValue: 1.0];
        
        let message = RTMPCommandMessage(commandName: .connect, transactionId: 1, commandObject: commandObject, optionalUserArguments: nil)
        
        
        /*
        RTMPChunk_0 metadata = {{0}};
        metadata.msg_stream_id = kControlChannelStreamId;
        metadata.msg_type_id = RTMP_PT_INVOKE;
         
        m_trackedCommands[m_numberOfInvokes] = "connect";
         
        
        metadata.msg_length.data = static_cast<int>( buff.size() );
        sendPacket(&buff[0], buff.size(), metadata);
         */
    }
    
    func parseCurrentData() -> Bool {
        return false
    }
    
    
    func sendBuffer() {
        /*
        if(m_ending) {
            return ;
        }
        
        std::shared_ptr<Buffer> buf = std::make_shared<Buffer>(size);
        buf->put(const_cast<uint8_t*>(data), size);
        
        const RTMPMetadata_t inMetadata = static_cast<const RTMPMetadata_t&>(metadata);
        
        m_jobQueue.enqueue([=]() {
        
        if(!this->m_ending) {
        static int c_count = 0;
        c_count ++;
        
        auto packetTime = std::chrono::steady_clock::now();
        
        std::vector<uint8_t> chunk;
        std::shared_ptr<std::vector<uint8_t>> outb = std::make_shared<std::vector<uint8_t>>();
        outb->reserve(size + 64);
        size_t len = buf->size();
        size_t tosend = std::min(len, m_outChunkSize);
        uint8_t* p;
        buf->read(&p, buf->size());
        uint64_t ts = inMetadata.getData<kRTMPMetadataTimestamp>() ;
        const int streamId = inMetadata.getData<kRTMPMetadataMsgStreamId>();
        
        #ifndef RTMP_CHUNK_TYPE_0_ONLY
        auto it = m_previousChunkData.find(streamId);
        if(it == m_previousChunkData.end()) {
#endif
// Type 0.
put_byte(chunk, ( streamId & 0x1F));
put_be24(chunk, static_cast<uint32_t>(ts));
put_be24(chunk, inMetadata.getData<kRTMPMetadataMsgLength>());
put_byte(chunk, inMetadata.getData<kRTMPMetadataMsgTypeId>());
put_buff(chunk, (uint8_t*)&m_streamId, sizeof(int32_t)); // msg stream id is little-endian
#ifndef RTMP_CHUNK_TYPE_0_ONLY
} else {
    // Type 1.
    put_byte(chunk, RTMP_CHUNK_TYPE_1 | (streamId & 0x1F));
    put_be24(chunk, static_cast<uint32_t>(ts - it->second)); // timestamp delta
    put_be24(chunk, inMetadata.getData<kRTMPMetadataMsgLength>());
    put_byte(chunk, inMetadata.getData<kRTMPMetadataMsgTypeId>());
}
#endif
m_previousChunkData[streamId] = ts;
put_buff(chunk, p, tosend);

outb->insert(outb->end(), chunk.begin(), chunk.end());

len -= tosend;
p += tosend;

while(len > 0) {
    tosend = std::min(len, m_outChunkSize);
    p[-1] = RTMP_CHUNK_TYPE_3 | (streamId & 0x1F);
    
    outb->insert(outb->end(), p-1, p+tosend);
    p+=tosend;
    len-=tosend;
    //  this->write(&outb[0], outb.size(), packetTime);
    //  outb.clear();
    
}

this->write(&(*outb)[0], outb->size(), packetTime, inMetadata.getData<kRTMPMetadataIsKeyframe>() );
}


});
  */
    }

    func sendPacket() {
        /*
        RTMPMetadata_t md(0.);
        
        md.setData(metadata.timestamp.data, metadata.msg_length.data, metadata.msg_type_id, metadata.msg_stream_id, false);
        
        pushBuffer(data, size, md);
  */
    }

}

// MARK: StreamSessionDelegate
extension RTMPSession: StreamSessionDelegate {
    func streamSession(session: StreamSession, didChangeStatus status: StreamEvent) {
        if status.contains(.openCompleted) && self.status.rawValue < RTMPStatus.connected.rawValue {
            self.status = [.connected, .handshakeStarted, .handshakeC0, .handshakeC1, .handshakeC2, .handshakeS0, .handshakeS1, .handshakeS2]
        }
        
        if status.contains(.hasBytesAvailable) {
            dataReceived()
        }
        
        if status.contains(.hasSpaceAvailable) {
            if self.status.rawValue < RTMPStatus.handshakeComplete.rawValue {
                handshake()
            }else{
                writeSemaphore.signal()
            }
        }
        
        if status.contains(.endEncountered) {
            self.status = .disconnected
        }
        
        if status.contains(.errorOccurred) {
            self.status = .error
        }
    }
}
