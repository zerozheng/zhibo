//
//  StreamSession.swift
//  zhiboApp
//
//  Created by zero on 17/2/23.
//  Copyright © 2017年 zero. All rights reserved.
//

import Foundation

public typealias StreamEvent = Stream.Event

public protocol StreamSessionDelegate: NSObjectProtocol {
    func streamSession(session: StreamSession, didChangeStatus status: StreamEvent)
}

public class StreamSession: NSObject {
    
    deinit {
        disconnet()
    }
    
    fileprivate func handleEvent(stream: Stream?, event: StreamEvent) {
        if event.contains(.openCompleted) {
            guard let _ = inputStream, let _ = outputStream, inputStream!.streamStatus.rawValue > 0, outputStream!.streamStatus.rawValue > 0, inputStream!.streamStatus.rawValue < 5, inputStream!.streamStatus.rawValue < 5 else {
                return
            }
            setStatus(.openCompleted, clear: true)
        }else if event.contains(.hasBytesAvailable) {
            setStatus(.hasBytesAvailable)
        }else if event.contains(.hasSpaceAvailable) {
            setStatus(.hasSpaceAvailable)
        }else if event.contains(.errorOccurred) {
            setStatus(.errorOccurred, clear: true)
        }else if event.contains(.endEncountered) {
            setStatus(.endEncountered, clear: true)
        }
    }
    
    
    fileprivate func startNetwork() {
        runloop = RunLoop.current
        inputStream?.delegate = self
        outputStream?.delegate = self
        
        inputStream?.schedule(in: runloop!, forMode: .defaultRunLoopMode)
        outputStream?.schedule(in: runloop!, forMode: .defaultRunLoopMode)
        
        inputStream?.open()
        outputStream?.open()
        runloop?.run()
    }
    
    
    fileprivate var innerStatus: StreamEvent
    fileprivate var inputStream: InputStream?
    fileprivate var outputStream: OutputStream?
    fileprivate weak var runloop: RunLoop?
    
    public weak var delegate: StreamSessionDelegate?
    
    init(delegate:StreamSessionDelegate? = nil) {
        self.delegate = delegate
        self.innerStatus = StreamEvent.init(rawValue: 0)
        super.init()
    }
    
}

let StreamSessionQueueLabel: String = "com.oralCare.network_StreamSession"

extension StreamSession: StreamSessional {
    
    public func connect(host: String, port: Int) {
        
        if innerStatus.rawValue > 0 {
            disconnet()
        }
        
        autoreleasepool { () -> () in
            var readStream: Unmanaged<CFReadStream>?
            var writeStream: Unmanaged<CFWriteStream>?
            
            CFStreamCreatePairWithSocketToHost(kCFAllocatorDefault, (host as CFString), UInt32(port), &readStream, &writeStream)
            
            inputStream = readStream?.takeRetainedValue()
            outputStream = writeStream?.takeRetainedValue()
            
            if let _ = inputStream, let _ = outputStream {
                DispatchQueue(label: StreamSessionQueueLabel).async {
                    self.startNetwork()
                }
            }else{
                handleEvent(stream: nil, event: .errorOccurred)
            }
        }
    }
    
    public func disconnet() {
        if let _ = outputStream {
            outputStream!.close()
            if let _ = runloop {
                outputStream!.remove(from: runloop!, forMode: .defaultRunLoopMode)
            }
            outputStream!.delegate = nil
            outputStream = nil
        }
        
        if let _ = inputStream {
            inputStream!.close()
            if let _ = runloop {
                inputStream!.remove(from: runloop!, forMode: .defaultRunLoopMode)
            }
            inputStream!.delegate = nil
            inputStream = nil
        }
        
        if let _ = runloop {
            CFRunLoopStop(runloop!.getCFRunLoop())
            runloop = nil
        }
        setStatus(StreamEvent.init(rawValue: 0), clear: true)
    }
    
    // 从buffer中读取数据到outputStream
    public func write(from buffer: UnsafeMutablePointer<UInt8>, size: Int) -> Int {
        var result: Int = 0
        guard let _ = outputStream else {
            return result
        }
        
        if outputStream!.hasSpaceAvailable {
            result = outputStream!.write(buffer, maxLength: size)
        }
        
        if result >= 0, result < size, innerStatus.contains(.hasSpaceAvailable) {
            innerStatus.remove(.hasSpaceAvailable)
        }
        
        return result;
    }
    
    //将inputStream的数据读到buffer中
    public func read(to buffer: UnsafeMutablePointer<UInt8>, size: Int) -> Int {
        var result: Int = 0
        guard let _ = inputStream else {
            return result
        }
        result = inputStream!.read(buffer, maxLength: size)
        
        if result < size, innerStatus.contains(.hasBytesAvailable) {
            innerStatus.remove(.hasBytesAvailable)
        }
        
        return result;
    }
    
    public func unsent() -> Int {
        return 0
    }
    
    public func unread() -> Int {
        return 0
    }
}

extension StreamSession {
    
    var status: StreamEvent {
        return innerStatus
    }
    
    fileprivate func setStatus(_ status: StreamEvent, clear: Bool = false) {
        if clear {
            innerStatus = status
        }else{
            innerStatus.insert(status)
        }
        if let _ = self.delegate {
            self.delegate!.streamSession(session: self, didChangeStatus: innerStatus)
        }
    }
}

extension StreamSession: StreamDelegate {
    public func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        handleEvent(stream: aStream, event: eventCode)
    }
}
