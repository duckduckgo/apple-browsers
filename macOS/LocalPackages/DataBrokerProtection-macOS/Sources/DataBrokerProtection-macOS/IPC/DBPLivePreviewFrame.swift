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
    public let pageURL: URL?
    public let canTakeControl: Bool
    public let isManualControl: Bool
    public let needsAssistance: Bool
    public let target: PIRLivePreviewTarget?
    public let checklist: PIRLivePreviewChecklist?

    init(frame: PIRLivePreviewFrame) {
        imageData = frame.imageData
        operationID = frame.operationID.uuidString
        brokerName = frame.brokerName
        activity = frame.activity
        faviconURL = frame.faviconURL
        pageURL = frame.pageURL
        canTakeControl = frame.canTakeControl
        isManualControl = frame.isManualControl
        needsAssistance = frame.needsAssistance
        target = frame.target
        checklist = frame.checklist
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
        pageURL = coder.decodeObject(of: NSURL.self, forKey: "pageURL") as URL?
        canTakeControl = coder.decodeBool(forKey: "canTakeControl")
        isManualControl = coder.decodeBool(forKey: "isManualControl")
        needsAssistance = coder.decodeBool(forKey: "needsAssistance")
        if let actionID = coder.decodeObject(of: NSString.self, forKey: "targetActionID") as String?,
           let rawType = coder.decodeObject(of: NSString.self, forKey: "targetActionType") as String?,
           let actionType = ActionType(rawValue: rawType),
           let values = coder.decodeArrayOfObjects(ofClass: NSNumber.self, forKey: "targetRects")?.map(\.doubleValue),
           values.count.isMultiple(of: 4) {
            let rects = stride(from: 0, to: values.count, by: 4).map {
                CGRect(x: values[$0], y: values[$0 + 1], width: values[$0 + 2], height: values[$0 + 3])
            }
            let texts = (coder.decodeArrayOfObjects(ofClass: NSString.self, forKey: "targetTexts") as [String]?)?
                .map { $0.isEmpty ? nil : $0 } ?? []
            target = PIRLivePreviewTarget(actionID: actionID, actionType: actionType, rects: rects, texts: texts)
        } else {
            target = nil
        }
        if let items = coder.decodeArrayOfObjects(ofClass: NSString.self, forKey: "checklistItems") as [String]? {
            checklist = PIRLivePreviewChecklist(isOptOut: coder.decodeBool(forKey: "checklistIsOptOut"),
                                                isConfirmation: coder.decodeBool(forKey: "checklistIsConfirmation"), items: items,
                                                currentIndex: coder.decodeInteger(forKey: "checklistCurrentIndex"))
        } else {
            checklist = nil
        }
    }

    public func encode(with coder: NSCoder) {
        coder.encode(imageData as NSData, forKey: "imageData")
        coder.encode(operationID as NSString, forKey: "operationID")
        coder.encode(brokerName as NSString, forKey: "brokerName")
        coder.encode(activity as NSString, forKey: "activity")
        coder.encode(faviconURL as NSURL?, forKey: "faviconURL")
        coder.encode(pageURL as NSURL?, forKey: "pageURL")
        coder.encode(canTakeControl, forKey: "canTakeControl")
        coder.encode(isManualControl, forKey: "isManualControl")
        coder.encode(needsAssistance, forKey: "needsAssistance")
        if let target {
            coder.encode(target.actionID as NSString, forKey: "targetActionID")
            coder.encode(target.actionType.rawValue as NSString, forKey: "targetActionType")
            let values = target.rects.flatMap { [$0.minX, $0.minY, $0.width, $0.height] }
            coder.encode(values.map { NSNumber(value: $0) } as NSArray, forKey: "targetRects")
            coder.encode(target.texts.map { $0 ?? "" } as NSArray, forKey: "targetTexts")
        }
        if let checklist {
            coder.encode(checklist.items as NSArray, forKey: "checklistItems")
            coder.encode(checklist.isOptOut, forKey: "checklistIsOptOut")
            coder.encode(checklist.isConfirmation, forKey: "checklistIsConfirmation")
            coder.encode(checklist.currentIndex, forKey: "checklistCurrentIndex")
        }
    }
}
#endif
