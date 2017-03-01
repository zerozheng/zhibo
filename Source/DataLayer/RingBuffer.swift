//
//  RingBuffer.swift
//  zhiboApp
//
//  Created by zero on 17/2/24.
//  Copyright © 2017年 zero. All rights reserved.
//

import Foundation

class RingBuffer {
    
    let buffer: UnsafeMutablePointer<UInt8>
    let capacity: Int
    
    var write: Int
    var read: Int
    var ring: Bool
    
    lazy var lock: NSLock = NSLock()
    
    init(capacity: Int) {
        self.capacity = capacity
        self.buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        self.buffer.initialize(to: 0)
        
        self.write = 0
        self.read = 0
        self.ring = false
    }
    
    deinit {
        self.buffer.deinitialize()
        self.buffer.deallocate(capacity: capacity)
    }
    
    //多少字节可写入
    func maxSpacesAvailable() -> Int {
        if write >= read {
            return capacity - write + read
        }else{
            return read - write
        }
    }
    
    //多少字节可读区
    func maxBytesAvailable() -> Int {
        if write > read {
            return write - read
        }else if write == read {
            if ring {
                return capacity
            }else{
                return 0
            }
        }else{
            return capacity - read + write
        }
    }
    
    func put(data: UnsafePointer<UInt8>, size: Int) -> Int {
        
        if size <= 0 { return 0 }
        lock.lock()
        let max = maxSpacesAvailable()
        let dataSize = size > max ? max : size
        if dataSize > 0 {
            let start = write
            let end = min(start + dataSize, capacity)
            let realSize = end - start
            memcpy(&buffer[start], data, realSize)
            write += realSize
            if realSize < dataSize {
                memcpy(&buffer[0], data.advanced(by: realSize), dataSize - realSize)
                write = dataSize - realSize
            }
            if write == read {
                ring = true
            }
        }
        lock.unlock()
        return dataSize
    }
    
    func get(buffer: UnsafeMutablePointer<UInt8>, size: Int, clear: Bool = false) -> Int {
        
        if size <= 0 {return 0}
        
        lock.lock()
        let max = maxBytesAvailable()
        let dataSize = size > max ? max : size
        if dataSize > 0 {
            let start = read
            let end = min((start + dataSize), capacity)
            let realSize = end - start
            memcpy(buffer, &self.buffer[start], realSize)
            if clear {
                memset(&self.buffer[start], 0, realSize)
            }
            read += realSize
            if realSize < dataSize {
                memcpy(buffer.advanced(by: realSize), &self.buffer[0], dataSize - realSize)
                if clear {
                    memset(&self.buffer[0], 0, dataSize - realSize)
                }
                read = dataSize - realSize
            }
            
            if ring {
                ring = false
            }
        }
        lock.unlock()
        return dataSize
    }
    
    func clear() {
        write = 0
        read = 0
        ring = false
    }
    
}


