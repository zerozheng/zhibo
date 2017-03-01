//
//  RandomData.swift
//  zhiboApp
//
//  Created by zero on 17/3/1.
//  Copyright © 2017年 zero. All rights reserved.
//

import Foundation

class RandomData {
    static func generateRandomData(withSize size: UInt) -> [UInt8] {
        var result: [UInt8] = []
        for _ in 0 ..< size {
            result.append(UInt8(arc4random()%256))
        }
        return result
    }
}
