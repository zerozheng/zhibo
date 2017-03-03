//
//  ByteRateManager.swift
//  zhiboApp
//
//  Created by zero on 17/2/27.
//  Copyright © 2017年 zero. All rights reserved.
//

import Foundation

typealias ByteRateCallback = (_ predictedBytesPerSecond: Double, _ currentBytesPerSecond: Double) ->()


class ByteRateManager {
    
    let kMeasurementDelay: TimeInterval = 2 //取样的间隔，每2秒一次
    var didSentBufferSize:[Int] //已经发送的buffer大小
    var willSendbufferSize:[Int] //即将发送的buffer大小
    var stopUpdate: Bool
    var started: Bool
    var callback: ByteRateCallback? = nil
    
    lazy var sentLock: NSLock = NSLock()
    lazy var bufferLock: NSLock = NSLock()
    lazy var condictionLock: NSConditionLock = NSConditionLock.init()
    
    init() {
        didSentBufferSize = []
        willSendbufferSize = []
        stopUpdate = true
        started = false
    }
    
    deinit {
        stopUpdate = true
    }
    
    func clear() {
        didSentBufferSize.removeAll()
        willSendbufferSize.removeAll()
        stopUpdate = true
        started = false
    }
    
    func start() {
        if !started {
            started = true
            stopUpdate = false
            DispatchQueue.global().async {
                self.sampleThread()
            }
        }
    }
    
    func sampleThread() {
        
        var preTime = NSDate()
        while(!stopUpdate) {
            if !stopUpdate {
                condictionLock.lock(before: Date(timeInterval: kMeasurementDelay, since: Date()))
            }
            
            if stopUpdate { break }
            let current = NSDate()
            let diff = current.timeIntervalSince1970 - preTime.timeIntervalSince1970
            preTime = current
            
            sentLock.lock()
            bufferLock.lock()
            
            let totalSent: Int = didSentBufferSize.reduce(0, +)
            let detectedBytesPerSec = Double(totalSent) / diff
            
            let totalWillSend: Int = willSendbufferSize.reduce(0, +)
            let predictedBytesPerSec = Double(totalWillSend) / diff
            
            didSentBufferSize.removeAll()
            sentLock.unlock()
            bufferLock.unlock()
            
            if callback != nil {
                callback!(predictedBytesPerSec, detectedBytesPerSec)
            }
        }
    }
}


extension ByteRateManager {
    func didSentBuffer(size: Int) {
        sentLock.lock()
        didSentBufferSize.append(size)
        sentLock.unlock()
    }
    
    func willSendBuffer(size: Int) {
        bufferLock.lock()
        willSendbufferSize.removeAll()
        willSendbufferSize.append(size)
        bufferLock.unlock()
    }
}
