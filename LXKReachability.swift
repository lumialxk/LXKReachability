//
//  LXKReachability.swift
//  Playground
//
//  Created by 李现科 on 15/12/28.
//  Copyright © 2015年 李现科. All rights reserved.
//

import Foundation
import SystemConfiguration
import CoreTelephony

enum NetworkStatus {
    case NotReachable
    case ReachableViaWiFi
    case ReachableViaWWAN
    case ReachableVia2G
    case ReachableVia3G
    case ReachableVia4G
}

public let kReachabilityChangedNotification = "kNetworkReachabilityChangedNotification"

class LXKReachability {
    
    private var alwaysReturnLocalWiFiStatus = false
    private var reachabilityRef = SCNetworkReachabilityRef?()
    private var reachabilityCallback: SCNetworkReachabilityCallBack = { (rachability: SCNetworkReachability, flags: SCNetworkReachabilityFlags, info: UnsafeMutablePointer<Void>) -> Void in
        let lxkReachability = unsafeBitCast(info, UnsafeMutablePointer<LXKReachability>.self).memory
        NSNotificationCenter.defaultCenter().postNotificationName(kReachabilityChangedNotification, object: lxkReachability)
    }
    
    
    //MARK: - Instance methods
    
    class func reachabilityWithHostName(hostName: String) -> LXKReachability? {
        var result: LXKReachability?
        let reachability = SCNetworkReachabilityCreateWithName(nil, (hostName as NSString).UTF8String)
        if reachability != nil {
            result = LXKReachability()
            if result != nil {
                result?.alwaysReturnLocalWiFiStatus = false
                result?.reachabilityRef = reachability
            }
        }
        
        return result
    }
    
    class func reachabilityWithAddress(hostAddress: sockaddr_in) -> LXKReachability? {
        var result: LXKReachability?
        var bytes: [Int8] = [Int8(hostAddress.sin_port>>8),Int8(hostAddress.sin_port),Int8(hostAddress.sin_addr.s_addr>>24),Int8(hostAddress.sin_addr.s_addr>>16),Int8(hostAddress.sin_addr.s_addr>>8),Int8(hostAddress.sin_addr.s_addr),hostAddress.sin_zero.0,hostAddress.sin_zero.1,hostAddress.sin_zero.2,hostAddress.sin_zero.3,hostAddress.sin_zero.4,hostAddress.sin_zero.5,hostAddress.sin_zero.6,hostAddress.sin_zero.7]
        let data = (bytes[0],bytes[1],bytes[2],bytes[3],bytes[4],bytes[5],bytes[6],bytes[7],bytes[8],bytes[9],bytes[10],bytes[11],bytes[12],bytes[13])
        var tmp = sockaddr(sa_len: hostAddress.sin_len, sa_family: hostAddress.sin_family, sa_data: data)
        let reachability = withUnsafePointer(&tmp) { (prt: UnsafePointer<sockaddr>) -> SCNetworkReachability? in
            return SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault, prt)
        }
        if reachability != nil {
            result = LXKReachability()
            if result != nil {
                result?.alwaysReturnLocalWiFiStatus = false
                result?.reachabilityRef = reachability
            }
        }
        
        return result
    }
    
    class func reachabilityForInternetConnection() -> LXKReachability? {
        var zeroAddress = sockaddr_in()
        bzero(&zeroAddress, sizeof(sockaddr_in))
        zeroAddress.sin_len = UInt8(sizeof(sockaddr_in))
        zeroAddress.sin_family = sa_family_t(AF_INET)
        
        return self.reachabilityWithAddress(zeroAddress)
    }
    
    class func reachabilityForLocalWiFi() -> LXKReachability? {
        var result: LXKReachability?
        var localWifiAddress = sockaddr_in()
        bzero(&localWifiAddress, sizeof(sockaddr_in))
        localWifiAddress.sin_len = UInt8(sizeof(sockaddr_in))
        localWifiAddress.sin_family = UInt8(AF_INET)
        localWifiAddress.sin_addr.s_addr = CFSwapInt32BigToHost(0xA9FE0000)
        
        result = self.reachabilityWithAddress(localWifiAddress)
        if result != nil {
            result?.alwaysReturnLocalWiFiStatus = true
        }
        
        return result
    }
    
    //MARK: - Start and stop Notifier
    
    func startNotifier() -> Bool {
        var result = false
        var context = SCNetworkReachabilityContext(version: 0, info: UnsafeMutablePointer(unsafeAddressOf(self)), retain: nil, release: nil, copyDescription: nil)
        withUnsafeMutablePointer(&context) { (prt: UnsafeMutablePointer<SCNetworkReachabilityContext> ) -> Void in
            if SCNetworkReachabilitySetCallback(reachabilityRef!, reachabilityCallback, prt) {
                if SCNetworkReachabilityScheduleWithRunLoop(reachabilityRef!, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode) {
                    result = true
                }
            }
        }
        
        return result
    }
    
    func stopNotifier() {
        if reachabilityRef != nil {
            SCNetworkReachabilityUnscheduleFromRunLoop(reachabilityRef!, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode)
        }
    }
    
    deinit {
        stopNotifier()
    }
    
    //MARK: - Network flag handler
    
    private func localWiFiStatusForFlags(flags: SCNetworkReachabilityFlags) -> NetworkStatus {
        var result = NetworkStatus.NotReachable
        if flags.rawValue & SCNetworkReachabilityFlags.IsDirect.rawValue != 0 && flags.rawValue & SCNetworkReachabilityFlags.Reachable.rawValue != 0 {
            result = .ReachableViaWiFi
        }
        
        
        return result
    }
    
    private func networkStatusForFlags(flags: SCNetworkReachabilityFlags) -> NetworkStatus {
        var result = NetworkStatus.NotReachable
        if flags.rawValue & SCNetworkReachabilityFlags.Reachable.rawValue == 0 {
            return .NotReachable
        }
        if flags.rawValue & SCNetworkReachabilityFlags.ConnectionRequired.rawValue == 0 {
            result = .ReachableViaWiFi
        }
        if flags.rawValue & SCNetworkReachabilityFlags.ConnectionOnDemand.rawValue != 0 || flags.rawValue & SCNetworkReachabilityFlags.ConnectionOnTraffic.rawValue != 0 {
            if flags.rawValue & SCNetworkReachabilityFlags.InterventionRequired.rawValue == 0 {
                result = .ReachableViaWiFi
            }
        }
        if flags.rawValue & SCNetworkReachabilityFlags.IsWWAN.rawValue == SCNetworkReachabilityFlags.IsWWAN.rawValue {
            let info = CTTelephonyNetworkInfo()
            let currentRadioAccessTechnology = info.currentRadioAccessTechnology
            if currentRadioAccessTechnology != nil {
                switch currentRadioAccessTechnology! {
                case CTRadioAccessTechnologyLTE:
                    result = .ReachableVia4G
                    break
                case CTRadioAccessTechnologyEdge:
                    fallthrough
                case CTRadioAccessTechnologyGPRS:
                    fallthrough
                case CTRadioAccessTechnologyCDMA1x:
                    result = .ReachableVia2G
                    break
                default:
                    result = .ReachableVia3G
                    break
                }
                return result
            }
            if flags.rawValue & SCNetworkReachabilityFlags.TransientConnection.rawValue == SCNetworkReachabilityFlags.TransientConnection.rawValue {
                if flags.rawValue & SCNetworkReachabilityFlags.ConnectionRequired.rawValue == SCNetworkReachabilityFlags.ConnectionRequired.rawValue {
                    result = .ReachableVia2G
                } else {
                    result = .ReachableVia3G
                }
                return result
            }
            result = .ReachableViaWWAN
        }
        
        return result
    }
    
    func connectionRequired() -> Bool {
        var result = false
        var flags = SCNetworkReachabilityFlags()
        withUnsafeMutablePointer(&flags) { (prt: UnsafeMutablePointer<SCNetworkReachabilityFlags>) -> Void in
            if SCNetworkReachabilityGetFlags(reachabilityRef!, prt) {
                result = flags.rawValue & SCNetworkReachabilityFlags.ConnectionRequired.rawValue != 0
            }
        }
        
        return result
    }
    
    func currentReachabilityStatus() -> NetworkStatus {
        var result = NetworkStatus.NotReachable
        var flags = SCNetworkReachabilityFlags()
        withUnsafeMutablePointer(&flags) { (prt: UnsafeMutablePointer<SCNetworkReachabilityFlags>) -> Void in
            if SCNetworkReachabilityGetFlags(reachabilityRef!, prt) {
                if alwaysReturnLocalWiFiStatus {
                    result = localWiFiStatusForFlags(flags)
                } else {
                    result = networkStatusForFlags(flags)
                }
            }
        }
        
        return result
    }
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
}