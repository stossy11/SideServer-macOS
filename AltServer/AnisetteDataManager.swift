//
//  AnisetteDataManager.swift
//  AltServer
//
//  Created by Riley Testut on 11/16/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import AppKit

private extension Bundle
{
    struct ID
    {
        static let mail = "com.apple.mail"    }
}

enum AnisetteFetchError: LocalizedError
{
    case unknownError
}



private extension ALTAnisetteData
{
    func sanitize(byReplacingBundleID bundleID: String)
    {
        guard let range = self.deviceDescription.lowercased().range(of: "(" + bundleID.lowercased()) else { return }
        
        var adjustedDescription = self.deviceDescription[..<range.lowerBound]
        adjustedDescription += "(com.apple.dt.Xcode/3594.4.19)>"
        
        self.deviceDescription = String(adjustedDescription)
    }
}

class AnisetteDataManager: NSObject
{
    static let shared = AnisetteDataManager()
    
    private var anisetteDataCompletionHandlers: [String: (Result<ALTAnisetteData, Error>) -> Void] = [:]
    private var anisetteDataTimers: [String: Timer] = [:]
    
    private override init()
    {
        super.init()
        
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(AnisetteDataManager.handleAnisetteDataResponse(_:)), name: Notification.Name("com.rileytestut.AltServer.AnisetteDataResponse"), object: nil)
    }
    
    func requestAnisetteData(_ completion: @escaping (Result<ALTAnisetteData, AnisetteFetchError>) -> Void)
    {
        guard let anisette = AOSKit.getAnisetteData() else {
            completion(.failure(.unknownError))
            return
        }
        completion(.success(anisette))
    }
}

private extension AnisetteDataManager
{
    @objc func handleAnisetteDataResponse(_ notification: Notification)
    {
        guard let userInfo = notification.userInfo, let requestUUID = userInfo["requestUUID"] as? String else { return }
                
        if
            let archivedAnisetteData = userInfo["anisetteData"] as? Data,
            let anisetteData = try? NSKeyedUnarchiver.unarchivedObject(ofClass: ALTAnisetteData.self, from: archivedAnisetteData)
        {
            anisetteData.sanitize(byReplacingBundleID: Bundle.ID.mail)
            self.finishRequest(forUUID: requestUUID, result: .success(anisetteData))
        }
        else
        {
            self.finishRequest(forUUID: requestUUID, result: .failure(ALTServerError(.invalidAnisetteData)))
        }
    }
    
    func finishRequest(forUUID requestUUID: String, result: Result<ALTAnisetteData, Error>)
    {
        let completionHandler = self.anisetteDataCompletionHandlers[requestUUID]
        self.anisetteDataCompletionHandlers[requestUUID] = nil
        
        let timer = self.anisetteDataTimers[requestUUID]
        self.anisetteDataTimers[requestUUID] = nil
        
        timer?.invalidate()
        completionHandler?(result)
    }
}
