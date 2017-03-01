//
//  StringExtension.swift
//  zhiboApp
//
//  Created by zero on 17/2/23.
//  Copyright © 2017年 zero. All rights reserved.
//

import Foundation

extension String {
    
    var url: URL? {
        return URL(string: self)
    }
    
    
    var scheme: String? {
        return url?.scheme
    }
    
    var host: String? {
        return url?.host
    }
    
    var port: Int? {
        return url?.port
    }
    
    var app: String? {
        guard var path = url?.path else {
            return nil
        }
        if path.hasPrefix("/") {
            path = path.substring(from: index(after: path.startIndex))
        }
        return path.components(separatedBy: "/").first
    }
    
    var playPath: String? {
        /*
        guard var path = url?.path else {
            return nil
        }
        if path.hasPrefix("/") {
            path = path.substring(from: index(after: path.startIndex))
        }
        var components = path.components(separatedBy: "/")
        guard components.count > 1 else {
            return nil
        }
        return components[1]
        */
        guard let path = url?.path, let appName = app else {
            return nil
        }
        
        let appPath = "/\(appName)/"
        
        if path.hasPrefix(appPath) {
            return path.substring(from: appPath.endIndex)
        }else{
            return nil
        }
    }
}
