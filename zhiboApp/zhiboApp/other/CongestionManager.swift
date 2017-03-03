//
//  CongestionManager.swift
//  zhiboApp
//
//  Created by zero on 17/3/2.
//  Copyright © 2017年 zero. All rights reserved.
//

import Foundation

class CongestionManager {
    
    var maxCongestionSize: Int
    var bufferSize: Int
    var lock: NSLock = NSLock()
    var clearDate: Date?
    
    init(maxCongestionSize: Int = 1024*1024*10) {
        bufferSize = 0
        self.maxCongestionSize = maxCongestionSize
    }
    
    func increase(size: Int, date: Date = Date()) {
        
        if clearDate != nil && clearDate! > date {
            return
        }
        lock.lock()
        bufferSize += size
        lock.unlock()
    }
    
    func clear() {
        bufferSize = 0
        clearDate = Date()
    }
}
