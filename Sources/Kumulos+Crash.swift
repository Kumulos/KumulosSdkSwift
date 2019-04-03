//
//  Kumulos+Crash.swift
//  KumulosSDK
//
//  Created by Andy on 26/06/2017.
//  Copyright © 2017 Kumulos. All rights reserved.
//

import Foundation
import KSCrash

public extension Kumulos {
    
    /**
     Send any pending reports to the API
     */
    internal func trackAndReportCrashes() {
        let url =  "\(baseCrashUrl)/track/\(apiKey)/kscrash/\(Kumulos.installId)"
        
        let installation = KSCrashInstallationStandard.sharedInstance()
        installation?.url = URL(string: url)
                
        installation?.install()
                
        installation?.sendAllReports { (reports, completed, error) -> Void in
            if(completed) {
                print("Sent \(String(describing: reports?.count)) reports")
            } else {
                print("Failed to send reports: \(String(describing: error))")
            }
        }
    }
    
    static func logException(name: String, reason: String, language: String, lineOfCode: String, stackTrace: [Any], logAllThreads: Bool)  {
        KSCrash.sharedInstance().reportUserException(name, reason: reason, language: language, lineOfCode: lineOfCode, stackTrace: stackTrace, logAllThreads: logAllThreads, terminateProgram: false)
        
        KSCrash.sharedInstance().sendAllReports{ (reports, completed, error) -> Void in
            if(completed) {
                print("Sent \(String(describing: reports?.count)) reports")
            } else {
                print("Failed to send reports: \(String(describing: error))")
            }
        }
    }
}
