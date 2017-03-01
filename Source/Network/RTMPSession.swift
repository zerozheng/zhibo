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
        super.init()
    }
    
    deinit {
        stop = true
    }
    
    
    // 推流链接
    fileprivate var urlString: String?
    // 写入信号
    fileprivate var writeSemaphore: DispatchSemaphore
    fileprivate var writeQueue: DispatchQueue
    fileprivate var streamInBuffer: RingBuffer
    fileprivate var s1: UnsafeMutablePointer<UInt8>?
    fileprivate var byteRateManager: ByteRateManager?
    fileprivate var stop: Bool
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
    }
    
}

// MARK: Private variable and method
extension RTMPSession {
    func reset() {
        status = .unconnect
        urlString = nil
        self.streamInBuffer.clear()
    }
    
    
    func write(data: UnsafePointer<UInt8>, size: Int) {
        
        guard size > 0 else { return }
        byteRateManager?.willSendBuffer(size: size)
        
        writeQueue.sync {
            var buf: UnsafeMutablePointer<UInt8> = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
            buf.assign(from: data, count: size)
            var sizeToSent = size
            while sizeToSent > 0 && !stop {
                let sent = streamSession.write(from: buf, size: sizeToSent)
                buf += sent
                sizeToSent -= sent
                byteRateManager?.didSentBuffer(size: sent)
                if sent == 0 {
                    let _ = writeSemaphore.wait(timeout: DispatchTime.now()+1)
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
        
    }
    
    func parseCurrentData() -> Bool {
        return false
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
