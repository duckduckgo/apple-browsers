//
//  PageContextExtractionOutcome.swift
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

public enum PageContextExtractionOutcome: Equatable {

    public enum FailureReason: String, Equatable {
        case emptyContent = "empty_content"
        case deserializeFailed = "deserialize_failed"
        case timeout
        case noWebView = "no_webview"
        case postFailed = "post_failed"
        case tabEvicted = "tab_evicted"
    }

    case success
    case failure(FailureReason)
    case prevented(String)
}

public extension PageContextExtractionOutcome {
    static let internalPageCategory = "internalPage"
}

public enum PageContextExtractionTrigger: String, Equatable {
    case auto
    case navigation
    case userRequest = "user_request"
    case tabContent = "tab_content"
}

public enum PageContextExtractionLatencyBucket: String, Equatable {
    case under1s = "under_1s"
    case oneToFiveSeconds = "1_to_5s"
    case over5s = "over_5s"

    public init(seconds: TimeInterval) {
        if seconds < 1 {
            self = .under1s
        } else if seconds <= 5 {
            self = .oneToFiveSeconds
        } else {
            self = .over5s
        }
    }
}
