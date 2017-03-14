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
    
    static var csid_0 = {return RTMPChunkStreamId(rawValue: 0x0)}()
    static var csid_1 = {return RTMPChunkStreamId(rawValue: 0x1)}()
    static var csid_2 = {return RTMPChunkStreamId(rawValue: 0x2)}()
}

class RTMPChunk {
    var chunkType: RTMPChunkType
    var timeStamp: TimeInterval
    var msgLength: Int
    var msgTypeId: Int
    var msgStreamId: Int
    
    init(chunkType: RTMPChunkType, timeStamp: TimeInterval, msgLenght: Int, msgTypeId: Int, msgStreamId: Int) {
        self.chunkType = chunkType
        self.timeStamp = timeStamp
        self.msgLength = msgLenght
        self.msgTypeId = msgTypeId
        self.msgStreamId = msgStreamId //litte-endian
    }
}

struct RTMPMessage {
    private(set) var timeStamp: TimeInterval
    private(set) var msgLength: Int
    private(set) var msgTypeId: Int
    private(set) var msgStreamId: Int //litte-endian
    private(set) var data: Data
}


/// RTMP消息类型
///
/// - 用户控制消息
///   - **userControl**: The client or the server sends this message to notify the peer about the user control events. This message carries Event type(2 bytes) and Event data.
///   - also see: **UserControlEventType**
/// - 协议控制消息
///   - **chunkSize**: This message is used to notify the peer of a new maximum chunk size, which is maintained independently for each direction. The payload is 4-byte length (32bit). The first bit must be zero, and the rest of 31 bit represent the chunk size to set.
///   - **abortMsg**: This message is used to notify the peer, which is waiting for chunks to complete a message, to discard the partially received message over a chunk stream. the payload is 4 bytes and represent the ID of the discarded stream.
///   - **acknowledgement**: This message is sent by client or server to notify the peer after receiving bytes equal to the window size. The payload is 4 bytes and holds the number of bytes received so far.
///   - **windowAcknowledgementSize**: This message is used by client or server to inform the peer of the window size to use between sending acknowledgments. The payload is 4 bytes and represent the size of the window.
///   - **peerBandwidth**: This message is sent by client or server to limit the output bandwidth of its peer. The peer receiving this message limits ith output bandwidth by limiting the amount of sent bu unacknowledged data to the window size indicated in this message. The peer receiving this message should respond with a Window Acknowledgment Size message if the window size is different from the last one sent to the sender of this message. The payload is 5 bytes. The first 4 bytes represent the window size, and the next 1 byte represent the type of limit. The limit type is one of the following values:
///     - 0: Hard. The peer should limit its output bandwidth to the indicated window size.
///     - 1: Soft. The peer should limit its output to the window indicated in this message or the limit already in effect, whichever is smaller.
///     - 2: Dynamic. If the previous limit type was hard, treat this message as though is was marked hard, otherwise ignore this message.
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


/// 用户控制消息的事件类型
///
/// - **streamBegin**: The server sends this event to notify the client that a stream has become functional and can be used for communication. By default, this event is sent on ID 0 after the application connect command is successfully received from the client. The event data is 4-byte and represents the stream ID of the stream that became functional.
/// - **streamEOF**: The server sends this event to notify the client that the playback of data is over as requested on this stream. No more data is sent without issuing additional commands. The client discards the messages received for the stream. The 4 bytes of event data represent the ID of the stream on which playback has ended.
/// - **streamDry**: The server sends this event to notify the client that there is no more data on the stream. If the server does not detect any message for a time period, it can notify the subscribed clients that the stream is dry. The 4 bytes of event data represent the stream ID of the dry stream.
/// - **setBufferLength**: The client sends this event to inform the server of the buffer size (in milliseconds) that is used to buffer any data coming over a stream. This event is sent before the server starts processing the stream. The first 4 bytes of the event data represent the stream ID and the next 4 bytes represent the buffer length, in milliseconds.
/// - **streamIsRecorded**: The server sends this event to notify the client that the stream is a recorded stream. The 4 bytes event data represent the stream ID of the recorded stream.
/// - **pingRequest**: The server sends this event to test whether the client is reachable. Event data is a 4-byte timestamp, representing the local server time when the server dispatched the command. The client responds with PingResponse on receiving MsgPingRequest.
/// - **pingResponse**: The client sends this event to the server in response to the ping request. The event data is a 4-byte timestamp, which was received with the PingRequest request.
enum UserControlEventType: Int {
    case streamBegin = 0
    case streamEOF = 1
    case streamDry = 2
    case setBufferLength = 3
    case streamIsRecorded = 4
    case pingRequest = 6
    case pingResponse = 7
}



enum CommandType: String {
    
    //netconnection
    case connect = "connect"
    case call = "call"
    case close = "close"
    case createStream = "createStream"
    
    
    //netstream
    case play = "play"
    case play2 = "play2"
    case deleteStream = "deleteStream"
    case closeStream = "closeStream"
    case receiveAudio = "receiveAudio"
    case receiveVideo = "receiveVideo"
    case publish = "publish"
    case seek = "seek"
    case pause = "pause"
}


// MARK: Connect Command About

struct ConnectCommandObjectName: RawRepresentable {
    typealias RawValue = String
    private(set) var rawValue: RawValue
    
    init(rawValue: RawValue) {
        self.rawValue = rawValue
    }
    
    static var app: ConnectCommandObjectName {
        return ConnectCommandObjectName.init(rawValue: "app")
    }
    
    static var flashver: ConnectCommandObjectName {
        return ConnectCommandObjectName.init(rawValue: "flashver")
    }
    
    static var swfUrl: ConnectCommandObjectName {
        return ConnectCommandObjectName.init(rawValue: "swfUrl")
    }
    
    static var tcUrl: ConnectCommandObjectName {
        return ConnectCommandObjectName.init(rawValue: "tcUrl")
    }
    
    static var fpad: ConnectCommandObjectName {
        return ConnectCommandObjectName.init(rawValue: "tcUrl")
    }
    
    static var audioCodecs: ConnectCommandObjectName {
        return ConnectCommandObjectName.init(rawValue: "audioCodecs")
    }
    
    static var videoCodecs: ConnectCommandObjectName {
        return ConnectCommandObjectName.init(rawValue: "audioCodecs")
    }
    
    static var videoFunction: ConnectCommandObjectName {
        return ConnectCommandObjectName.init(rawValue: "videoFunction")
    }
    
    static var pageUrl: ConnectCommandObjectName {
        return ConnectCommandObjectName.init(rawValue: "pageUrl")
    }
    
    static var objectEncoding: ConnectCommandObjectName {
        return ConnectCommandObjectName.init(rawValue: "objectEncoding")
    }
}

typealias CCOName = ConnectCommandObjectName


enum AudioCodecsType: Int {
    case none = 0x0001
    case adpcm = 0x0002
    case mp3 = 0x0004
    case intel = 0x0008
    case unused = 0x0010
    case nelly8 = 0x0020
    case nelly = 0x0040
    case g711a = 0x0080
    case g711u = 0x0100
    case nelly16 = 0x0200
    case aac = 0x0400
    case speex = 0x0800
    case all = 0x0fff
}


enum VideoCodecsType: Int {
    case unused = 0x0001
    case jpeg = 0x0002
    case sorenson = 0x0004
    case homebrew = 0x0008
    case vp6 = 0x0010
    case vp6alpha = 0x0020
    case homebrewv = 0x0040
    case h264 = 0x0080
    case all = 0x00ff
}

enum VideoFunctionType: Int {
    case seek = 1
}


enum EncodingType: Int {
    case amf0 = 0
    case amf3 = 3
}

class RTMPCommandMessage {
    private(set) var commandName: CommandType
    private(set) var transactionId: Int
    private(set) var commandObject: [String:AFM0Encoder]?
    private(set) var optionalUserArguments: [String:AFM0Encoder]?
    
    init(commandName: CommandType, transactionId: Int, commandObject: [String:AFM0Encoder]?, optionalUserArguments: [String:AFM0Encoder]?) {
        self.commandName = commandName
        self.transactionId = transactionId
        self.commandObject = commandObject
        self.optionalUserArguments = optionalUserArguments
    }
    
    func buffer() -> Data? {
        var data: Data = Data()
        do {
            try commandName.rawValue.append(to: &data)
        } catch {
            if error is RTMPError {
                print((error as! RTMPError).errorDescription)
            }else{
                print("unknown error happen")
            }
            return nil
        }
        
        do {
            try transactionId.append(to: &data)
        } catch {
            if error is RTMPError {
                print((error as! RTMPError).errorDescription)
            }else{
                print("unknown error happen")
            }
            return nil
        }
        
        do {
            try commandObject?.append(to: &data)
        } catch {
            if error is RTMPError {
                print((error as! RTMPError).errorDescription)
            }else{
                print("unknown error happen")
            }
            return nil
        }
        
        do {
            try optionalUserArguments?.append(to: &data)
        } catch {
            if error is RTMPError {
                print((error as! RTMPError).errorDescription)
            }else{
                print("unknown error happen")
            }
            return nil
        }
        
        return data
    }
    
}


enum AFM0DataType: UInt8 {
    case number = 0
    case boolean = 1
    case string = 2
    case object = 3
    case movieClip = 4  /* reserved, not used */
    case null = 5
    case undefined = 6
    case reference = 7
    case arrayEMCA = 8
    case objectEnd = 9
    case arrayStrict = 10
    case date = 11
    case longString = 12
    case unsupported = 13
    case recordSet = 14 /* reserved, not used */
    case xml = 15
    case typedObject = 16
    case avmPlus = 17   /* switch to AMF3 */
    case invalid = 0xff
}
