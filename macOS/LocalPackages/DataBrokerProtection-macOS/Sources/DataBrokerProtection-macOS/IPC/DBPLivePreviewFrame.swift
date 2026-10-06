//
//  DBPLivePreviewFrame.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#if DEBUG
import Foundation
import DataBrokerProtectionCore

@objc(DBPLivePreviewFrame)
public final class DBPLivePreviewFrame: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }

    public let imageData: Data
    public let operationID: String
    public let brokerName: String
    public let activity: String
    public let faviconURL: URL?
    public let canTakeControl: Bool
    public let isManualControl: Bool

    init(frame: PIRLivePreviewFrame) {
        imageData = frame.imageData
        operationID = frame.operationID.uuidString
        brokerName = frame.brokerName
        activity = frame.activity
        faviconURL = frame.faviconURL
        canTakeControl = frame.canTakeControl
        isManualControl = frame.isManualControl
    }

    public init?(coder: NSCoder) {
        guard let imageData = coder.decodeObject(of: NSData.self, forKey: "imageData") as Data?,
              let operationID = coder.decodeObject(of: NSString.self, forKey: "operationID") as String?,
              let brokerName = coder.decodeObject(of: NSString.self, forKey: "brokerName") as String?,
              let activity = coder.decodeObject(of: NSString.self, forKey: "activity") as String? else { return nil }
        self.imageData = imageData
        self.operationID = operationID
        self.brokerName = brokerName
        self.activity = activity
        faviconURL = coder.decodeObject(of: NSURL.self, forKey: "faviconURL") as URL?
        canTakeControl = coder.decodeBool(forKey: "canTakeControl")
        isManualControl = coder.decodeBool(forKey: "isManualControl")
    }

    public func encode(with coder: NSCoder) {
        coder.encode(imageData as NSData, forKey: "imageData")
        coder.encode(operationID as NSString, forKey: "operationID")
        coder.encode(brokerName as NSString, forKey: "brokerName")
        coder.encode(activity as NSString, forKey: "activity")
        coder.encode(faviconURL as NSURL?, forKey: "faviconURL")
        coder.encode(canTakeControl, forKey: "canTakeControl")
        coder.encode(isManualControl, forKey: "isManualControl")
    }
}
#endif
