//
//  RTMPError.swift
//  zhiboApp
//
//  Created by zero on 17/3/14.
//  Copyright © 2017年 zero. All rights reserved.
//

import Foundation

enum RTMPError: Error {
    
    enum UrlPathError {
        case pathNotExists
        case hostNotExists
    }
    
    enum AFM0EncodeError {
        case stringOutOfSize
    }
    
    case urlPathError(reason: UrlPathError)
    case afm0EncodeError(reason: AFM0EncodeError)
}

extension RTMPError: LocalizedError {
    public var errorDescription: String {
        switch self {
        case .urlPathError(let reason):
            return reason.localizedDescription
        case .afm0EncodeError(let reason):
            return reason.localizedDescription
        }
    }
}

extension RTMPError.UrlPathError {
    var localizedDescription: String {
        switch self {
        case .pathNotExists:
            return "The path to connect is not exists"
        case .hostNotExists:
            return "The host to connect is not exists"
        }
    }
}

extension RTMPError.AFM0EncodeError {
    var localizedDescription: String {
        switch self {
        case .stringOutOfSize:
            return "The max length string using AFM0 Encoding is 0xFFFFFFFF"
        }
    }
}
