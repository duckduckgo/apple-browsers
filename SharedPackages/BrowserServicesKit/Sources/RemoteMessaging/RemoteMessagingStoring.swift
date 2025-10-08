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

public protocol RemoteMessagingStoring: RemoteMessagingStoringDebuggingSupport {

    func saveProcessedResult(_ processorResult: RemoteMessagingConfigProcessor.ProcessorResult) async
    func fetchRemoteMessagingConfig() -> RemoteMessagingConfig?
    func fetchScheduledRemoteMessage(surfaces: RemoteMessageSurfaceType) -> RemoteMessageModel?
    func hasShownRemoteMessage(withID id: String) -> Bool
    func fetchShownRemoteMessageIDs() -> [String]
    func dismissRemoteMessage(withID id: String) async
    func fetchDismissedRemoteMessageIDs() -> [String]
    func updateRemoteMessage(withID id: String, asShown shown: Bool) async

}
