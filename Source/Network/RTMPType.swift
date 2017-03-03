//
//  RTMPType.swift
//  zhiboApp
//
//  Created by zero on 17/2/23.
//  Copyright © 2017年 zero. All rights reserved.
//

import Foundation

let RTMPScheme: String = "rtmp"
let RTMPDefaultPort: Int = 1935
let RTMPBufferSize: Int = 4096
let RTMPSignatureSize: Int = 1536


/**
 * Chunk类型
 *
 * 0 表示messageHeader信息齐全
 * 1 表示messageHeader使用跟上一次相同msgStreamId
 * 2 表示messageHeader跟上一次仅时间戳不一样
 * 3 表示messageHeader跟上一次的一样
 */
struct RTMPChunkType: RawRepresentable {
    var rawValue: UInt8
    init(rawValue: UInt8) {
        self.rawValue = rawValue
    }
    
    static var type_00 = {return RTMPChunkType(rawValue: 0x0)}()
    static var type_01 = {return RTMPChunkType(rawValue: 0x40)}()
    static var type_10 = {return RTMPChunkType(rawValue: 0x80)}()
    static var type_11 = {return RTMPChunkType(rawValue: 0xC0)}()
}

/**
 * CSID
 *
 * 0 表示BasicHeader 占2个字节
 * 1 表示BasicHeader 占3个字节
 * 2 表示该chunk是控制信息／命令信息
 * 3~(2^16+2^6-1) 为自定义id
 */
struct RTMPChunkStreamId: RawRepresentable {
    var rawValue: UInt8
    init(rawValue: UInt8) {
        self.rawValue = rawValue
    }
    
    static var type_0 = {return RTMPChunkType(rawValue: 0x0)}()
    static var type_1 = {return RTMPChunkType(rawValue: 0x1)}()
    static var type_2 = {return RTMPChunkType(rawValue: 0x2)}()
}

class RTMPChunk {
    var chunkType: RTMPChunkType
    var timeStamp: TimeInterval
    var msgLenght: Int
    var msgTypeId: Int
    var msgStreamId: Int
    
    init(chunkType: RTMPChunkType, timeStamp: TimeInterval, msgLenght: Int, msgTypeId: Int, msgStreamId: Int) {
        self.chunkType = chunkType
        self.timeStamp = timeStamp
        self.msgLenght = msgLenght
        self.msgTypeId = msgTypeId
        self.msgStreamId = msgStreamId
    }
}



enum MessageType: Int {
    case chunkSize = 1
    case abortMsg = 2
    case acknowledgement = 3
    case userControl = 4
    case windowAcknowledgementSize = 5
    case peerBandwidth = 6
    case audio = 8
    case vedio = 9
    case afm3CommandMsg = 17
    case afm0CommandMsg = 20
    
    case afm3DataMsg = 15
    case afm0DataMsg = 18
    
    case afm3SharedObjectMsg = 16
    case afm0SharedObjectMsg = 19
    case aggregate = 22
    
}
