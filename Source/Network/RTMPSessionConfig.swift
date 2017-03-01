//
//  RTMPSessionConfig.swift
//  zhiboApp
//
//  Created by zero on 17/2/23.
//  Copyright © 2017年 zero. All rights reserved.
//

import Foundation

struct RTMPSessionParameter {
    var width: UInt32
    var height: UInt32
    var frameDurantion: Double
    var videoBitrate: UInt32
    var audioFrequency: Double
    var stereo: Bool
}

struct RTMPSessionMetaData {
    var timeStamp: UInt32
    var msgLength: UInt32
    var typeID: Double
    var msgStreamID: UInt32
    var isKeyFrame: Bool
}
