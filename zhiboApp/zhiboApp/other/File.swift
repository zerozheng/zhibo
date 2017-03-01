//
//  File.swift
//  zhiboApp
//
//  Created by zero on 17/2/27.
//  Copyright © 2017年 zero. All rights reserved.
//

import Foundation

class BufferManager {
    
    var sentBufferSize:[Int]
    var bufferSize:[Int]
    lazy var sentLock: NSLock = NSLock()
    lazy var bufferLock: NSLock = NSLock()
    
    let kPivotSamples: Int = 5
    let kMeasurementDelay: TimeInterval = 2 // seconds - represents the time between measurements when increasing or decreasing bitrate
    let kSettlementDelay: TimeInterval = 30 // seconds - represents time to wait after a bitrate decrease before attempting to increase again
    let kIncreaseDelta: TimeInterval = 10  // seconds - number of seconds to wait between increase vectors (after initial ramp up)
    
    var stopUpdate: Bool
    var hasFirstTurndown: Bool
    var started: Bool
    var sampleCount: Int
    var previousVector: Int
    
    var callback: ((_ recommendBitrate: Int, _ predictedBytesPerSecond: Double, _ immediateBytesPerSecond: Double) ->())? = nil
    
    var bwSamples: [Double]
    var buffGrowth: [Int]
    var turnSamples: [Double]
    
    var previousTurndown: TimeInterval
    var previousIncrease: TimeInterval
    
    lazy var condictionLock: NSConditionLock = NSConditionLock.init()
    
    init() {
        sentBufferSize = []
        bufferSize = []
        stopUpdate = true
        hasFirstTurndown = false
        started = false
        sampleCount = 30
        previousVector = 0
        bwSamples = []
        buffGrowth = []
        turnSamples = []
        previousTurndown = 0
        previousIncrease = 0
    }
    
    func clear() {
        sentBufferSize.removeAll()
        bufferSize.removeAll()
        stopUpdate = true
        hasFirstTurndown = false
        started = false
        sampleCount = 30
        previousVector = 0
        bwSamples.removeAll()
        buffGrowth.removeAll()
        turnSamples.removeAll()
        previousTurndown = 0
        previousIncrease = 0
    }
    
    func addSentBuffer(size: Int) {
        sentLock.lock()
        sentBufferSize.append(size)
        sentLock.unlock()
    }
    
    func addBuffer(size: Int) {
        bufferLock.lock()
        bufferSize.append(size)
        bufferLock.unlock()
    }
    
    
    
    deinit {
        stopUpdate = true
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
            
            let previousTurndownDiff = current.timeIntervalSince1970 - previousTurndown;
            let previousIncreaseDiff = current.timeIntervalSince1970 - previousIncrease;
            
            sentLock.lock()
            bufferLock.lock()
            
            let totalSent: Int = sentBufferSize.reduce(0, +)
            
            let detectedBytesPerSec = Double(totalSent) / diff
            var vec = 0
            var turnAvg: Double = 0
            
            bwSamples.insert(detectedBytesPerSec, at: 0)
            if bwSamples.count > sampleCount {
                let _ = bwSamples.popLast()
            }
            
            if !bufferSize.isEmpty {
                let lastSize: Int = bufferSize.last!
                buffGrowth.insert(lastSize, at: 0)
                if buffGrowth.count > 3 {
                    let _ = buffGrowth.popLast()
                }
                
                var buffGrowthAvg = 0
                var preValue = 0
                for growth in buffGrowth {
                    buffGrowthAvg += (growth > preValue) ? -1 : (growth < preValue ? 1 : 0)
                    preValue = growth
                }
                
                if buffGrowthAvg <= 0 && (!hasFirstTurndown || (previousTurndownDiff > kSettlementDelay && previousIncreaseDiff > kIncreaseDelta)) {
                    vec = 1
                }else if buffGrowthAvg > 0 {
                    vec = -1
                    hasFirstTurndown = true
                    previousTurndown = current.timeIntervalSince1970
                }else{
                    vec = 0
                }
                
                if previousVector < 0 && vec >= 0 {
                    let first: Double = bwSamples.first!
                    turnSamples.insert(first, at: 0)
                    if turnSamples.count > kPivotSamples {
                        let _ = turnSamples.popLast()
                    }
                }
                
                turnAvg = turnSamples.count == 0 ? turnAvg : turnSamples.reduce(0, +) / Double(turnSamples.count)
                
                if detectedBytesPerSec > turnAvg {
                    turnSamples.insert(detectedBytesPerSec, at: 0)
                    if turnSamples.count > kPivotSamples {
                        let _ = turnSamples.popLast()
                    }
                }
                
                previousVector = vec
            }
            
            sentBufferSize.removeAll()
            bufferSize.removeAll()
            sentLock.unlock()
            bufferLock.unlock()
            
            if callback != nil {
                if vec > 0 {
                    previousIncrease = current.timeIntervalSince1970
                }
                callback!(vec, turnAvg, detectedBytesPerSec)
            }
        }
    }
    
    
    
}
