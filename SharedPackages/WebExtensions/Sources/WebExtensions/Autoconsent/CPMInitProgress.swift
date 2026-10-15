//
//  CPMInitProgress.swift
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

import Foundation

/// How far the CPM extension's background got with a main frame's `init` message, as the extension reports it
/// through the `cpmInitProgress` native message. The extension only tells the app that a dashboard refresh is
/// due after it has awaited its configuration and the native setting checks, so without these marks a navigation
/// whose `init` never reached the background cannot be told from one that reached it and was slow.
public enum CPMInitProgressStage: String, Sendable {
    /// The background received `init`, before it did anything else with it.
    case received
    /// The background's `initResp` reached the page's content script.
    case responseSent = "response_sent"
    /// The background's `initResp` could not be delivered: the content script was gone.
    case responseFailed = "response_failed"
}

/// One progress mark kept until the navigation it belongs to reports a failure. Holds a URL only in memory and
/// only to match it to a navigation; the URL is never serialized.
struct CPMInitProgressRecord: Equatable, Sendable {
    let extensionTabIdentifier: Int?
    let url: URL
    let stage: CPMInitProgressStage
    let receivedAt: Date
}
