//
//  StreamSessional.swift
//  zhiboApp
//
//  Created by zero on 17/2/17.
//  Copyright © 2017年 zero. All rights reserved.
//

import Foundation

public protocol StreamSessional {
    
    func connect(host: String, port: Int)
    func disconnet()
    
    func write(from buffer: UnsafeMutablePointer<UInt8>, size: Int) -> Int
    func read(to buffer: UnsafeMutablePointer<UInt8>, size: Int) -> Int
    
    func unsent() -> Int
    func unread() -> Int
    
}
