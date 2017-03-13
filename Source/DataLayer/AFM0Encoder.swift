//
//  AFM0Encoder.swift
//  zhiboApp
//
//  Created by zero on 17/3/10.
//  Copyright © 2017年 zero. All rights reserved.
//

import Foundation


public protocol AFM0Encoder {
    func append(to data: inout Data) throws -> Void
}

extension String: AFM0Encoder {
    public func append(to data: inout Data) throws {
        let count: Int64 = Int64(self.utf8.count)
        if count <= 0xFFFF {
            data.append(AFM0DataType.string.rawValue)
            let rawPointer = UnsafeMutableRawPointer.allocate(bytes: 2, alignedTo: MemoryLayout<UInt8>.alignment)
            rawPointer.storeBytes(of: UInt16(count), as: UInt16.self)
            defer {
                rawPointer.deallocate(bytes: 2, alignedTo: MemoryLayout<UInt8>.alignment)
            }
            data.append(Data(bytes: rawPointer, count: 2))
            self.utf8.forEach{ data.append($0) }
        }else if count <= 0xFFFFFFFF {
            data.append(AFM0DataType.longString.rawValue)
            let rawPointer = UnsafeMutableRawPointer.allocate(bytes: 4, alignedTo: MemoryLayout<UInt8>.alignment)
            rawPointer.storeBytes(of: UInt32(count), as: UInt32.self)
            defer {
                rawPointer.deallocate(bytes: 4, alignedTo: MemoryLayout<UInt8>.alignment)
            }
            data.append(Data(bytes: rawPointer, count: 4))
            self.utf8.forEach{ data.append($0) }
        }else{
            throw AFM0EncodeError.stringOutOfSize
            //throw "the string encoder with AFM0 is more than 0xFFFFFFFF"
        }
    }
}

extension Double: AFM0Encoder {
    public func append(to data: inout Data) throws {
        data.append(AFM0DataType.number.rawValue)
        let rawPointer = UnsafeMutableRawPointer.allocate(bytes: 8, alignedTo: MemoryLayout<UInt8>.alignment)
        rawPointer.storeBytes(of: CFConvertDoubleHostToSwapped(self).v, as: UInt64.self)
        defer {
            rawPointer.deallocate(bytes: 8, alignedTo: MemoryLayout<UInt8>.alignment)
        }
        data.append(Data(bytes: rawPointer, count: 8))
    }
}

extension Float: AFM0Encoder {
    public func append(to data: inout Data) throws {
        do {
            try Double(self).append(to: &data)
        } catch let error {
            throw error
        }
    }
}

extension Int: AFM0Encoder {
    public func append(to data: inout Data) throws {
        do {
            try Double(self).append(to: &data)
        } catch let error {
            throw error
        }
    }
}

extension UInt: AFM0Encoder {
    public func append(to data: inout Data) throws {
        do {
            try Double(self).append(to: &data)
        } catch let error {
            throw error
        }
    }
}

extension Int64: AFM0Encoder {
    public func append(to data: inout Data) throws {
        do {
            try Double(self).append(to: &data)
        } catch let error {
            throw error
        }
    }
}

extension UInt64: AFM0Encoder {
    public func append(to data: inout Data) throws {
        do {
            try Double(self).append(to: &data)
        } catch let error {
            throw error
        }
    }
}

extension Int32: AFM0Encoder {
    public func append(to data: inout Data) throws {
        do {
            try Double(self).append(to: &data)
        } catch let error {
            throw error
        }
    }
}

extension UInt32: AFM0Encoder {
    public func append(to data: inout Data) throws {
        do {
            try Double(self).append(to: &data)
        } catch let error {
            throw error
        }
    }
}

extension Int16: AFM0Encoder {
    public func append(to data: inout Data) throws {
        do {
            try Double(self).append(to: &data)
        } catch let error {
            throw error
        }
    }
}

extension UInt16: AFM0Encoder {
    public func append(to data: inout Data) throws {
        do {
            try Double(self).append(to: &data)
        } catch let error {
            throw error
        }
    }
}

extension Int8: AFM0Encoder {
    public func append(to data: inout Data) throws {
        do {
            try Double(self).append(to: &data)
        } catch let error {
            throw error
        }
    }
}

extension UInt8: AFM0Encoder {
    public func append(to data: inout Data) throws {
        do {
            try Double(self).append(to: &data)
        } catch let error {
            throw error
        }
    }
}

extension Bool: AFM0Encoder {
    public func append(to data: inout Data) throws {
        data.append(AFM0DataType.boolean.rawValue)
        if self == true {
            data.append(0)
        }else{
            data.append(1)
        }
    }
}

extension Sequence where Iterator.Element == (key: String, value: AFM0Encoder) {
    public func append(to data: inout Data) throws {
        data.append(AFM0DataType.object.rawValue)
        
        if self.underestimatedCount == 0 { return }
        
        for (key, value) in self {
            //write the key
            let count: Int64 = Int64(key.utf8.count)
            if count <= 0xFFFF {
                let rawPointer = UnsafeMutableRawPointer.allocate(bytes: 2, alignedTo: MemoryLayout<UInt8>.alignment)
                rawPointer.storeBytes(of: UInt16(count), as: UInt16.self)
                defer {
                    rawPointer.deallocate(bytes: 2, alignedTo: MemoryLayout<UInt8>.alignment)
                }
                data.append(Data(bytes: rawPointer, count: 2))
                key.utf8.forEach{ data.append($0) }
            }else{
                throw AFM0EncodeError.stringOutOfSize
            }
            
            //write the value
            do {
                try value.append(to: &data)
            }catch let error {
                throw error
            }
        }
        data.append(0x00)
        data.append(0x00)
        data.append(AFM0DataType.objectEnd.rawValue)
    }
}

enum AFM0EncodeError: Error {
    case stringOutOfSize
}
