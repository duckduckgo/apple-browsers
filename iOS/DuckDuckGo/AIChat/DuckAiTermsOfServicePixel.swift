//
//  DuckAiTermsOfServicePixel.swift
//  DuckDuckGo
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
import PixelKit

enum DuckAiTermsOfServicePixel: PixelKit.Event {

    /// The web app's record held an acceptance the app didn't have, so the app adopted it.
    case acceptedFromWeb

    /// The web app asked an already-accepted user to accept again; reports what its page could read.
    case duplicateAcceptanceContext(DuplicateAcceptanceContext)

    var name: String {
        switch self {
        case .acceptedFromWeb: return "aichat_terms_accepted_from_web"
        case .duplicateAcceptanceContext: return "aichat_terms_accepted_duplicate_context"
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .acceptedFromWeb:
            return nil
        case .duplicateAcceptanceContext(let context):
            return [
                "native_storage": context.isNativeStorageBridgeAvailable ? "available" : "unavailable",
                "tab": context.isFireTab ? "fire" : "standard",
                "web_record_at_load": context.pageLoad.webRecord.rawValue,
                "entries_migration_at_load": context.pageLoad.entriesMigration.rawValue
            ]
        }
    }

    var standardParameters: [PixelKitStandardParameter]? { nil }
}

struct DuplicateAcceptanceContext: Equatable {
    let isNativeStorageBridgeAvailable: Bool
    let isFireTab: Bool
    let pageLoad: DuckAiTermsOfServicePageLoadState
}

/// What the web app could read from native storage when its page last asked for the native config.
struct DuckAiTermsOfServicePageLoadState: Equatable {

    enum WebRecord: String {
        case accepted
        case missing
        case unknown
    }

    enum EntriesMigration: String {
        case done
        case pending
        case unknown
    }

    let webRecord: WebRecord
    let entriesMigration: EntriesMigration

    static let unknown = DuckAiTermsOfServicePageLoadState(webRecord: .unknown, entriesMigration: .unknown)
}
