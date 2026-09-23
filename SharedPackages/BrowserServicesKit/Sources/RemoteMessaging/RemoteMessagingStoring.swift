//
//  RemoteMessagingStoring.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

import Foundation

public protocol RemoteMessagingStoringDebuggingSupport {
    func resetRemoteMessages() async
}

public enum RemoteMessageImpressionResult: Equatable {
    case notRecorded
    case recorded(isFirstImpression: Bool, impressionCount: Int64?)
}

public protocol RemoteMessagingStoring: RemoteMessagingStoringDebuggingSupport {

    func saveProcessedResult(_ processorResult: RemoteMessagingConfigProcessor.ProcessorResult) async
    func fetchRemoteMessagingConfig() -> RemoteMessagingConfig?
    func fetchScheduledRemoteMessage(surfaces: RemoteMessageSurfaceType, triggerFilter: TriggerFilter) -> RemoteMessageModel?
    func hasShownRemoteMessage(withID id: String) -> Bool
    func fetchShownRemoteMessageIDs() -> [String]
    func dismissRemoteMessage(withID id: String) async
    func fetchDismissedRemoteMessageIDs() -> [String]
    /// Passing `true` records a countable impression while preserving the first-shown timestamp.
    /// Call this only after the surface confirms the message appeared, at the same point as its shown pixel.
    func updateRemoteMessage(withID id: String, asShown shown: Bool) async
    /// Records one confirmed impression and reports whether it was the first persisted impression.
    func recordRemoteMessageImpression(withID id: String) async -> RemoteMessageImpressionResult

}

public extension RemoteMessagingStoring {
    func fetchScheduledRemoteMessage(surfaces: RemoteMessageSurfaceType) -> RemoteMessageModel? {
        fetchScheduledRemoteMessage(surfaces: surfaces, triggerFilter: .noTrigger)
    }

    /// Compatibility bridge for stores that predate serialized impression recording. Concrete stores should override this
    /// operation so the first-impression check and increment happen in one serialized transaction.
    func recordRemoteMessageImpression(withID id: String) async -> RemoteMessageImpressionResult {
        let isFirstImpression = !hasShownRemoteMessage(withID: id)
        await updateRemoteMessage(withID: id, asShown: true)
        guard hasShownRemoteMessage(withID: id) else { return .notRecorded }
        return .recorded(isFirstImpression: isFirstImpression, impressionCount: nil)
    }
}
