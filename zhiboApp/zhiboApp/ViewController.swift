//
//  ViewController.swift
//  zhiboApp
//
//  Created by zero on 17/2/17.
//  Copyright © 2017年 zero. All rights reserved.
//

import UIKit

class ViewController: UIViewController {

    lazy var rmtpSession: RTMPSession = {
        return RTMPSession(delegate: self)
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        rmtpSession.connect(withUrlString: "rtmp://192.168.31.216:1935/live/123")
        
        //let streamSession: StreamSession = StreamSession()
        
    }
}


extension ViewController: RTMPSessionDelegate {
    func rtmpSession(session: RTMPSession, didChangeStatus status: RTMPStatus) {
        debugPrint(status)
    }
}
