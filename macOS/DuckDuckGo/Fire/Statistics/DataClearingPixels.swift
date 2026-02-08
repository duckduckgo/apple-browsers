//
//  DataClearingPixels.swift
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

enum DataClearingPixels {

    // Overall Flow Metrics

    /// Fire completed
    case fireCompletion(duration: Int, option: String, domains: String, path: String, autoClear: String)

    /// Fire button retriggered within 20 seconds
    case retriggerIn20s

    // Per-Action Quality Metrics

    case burnWebCacheError(Error)
    case burnWebCacheDuration(Int)
    case burnWebCacheHasResidue(steps: String)

    case burnHistoryError(Error)
    case burnHistoryDuration(entity: String, duration: Int)

    case burnChatHistoryError(Error)
    case burnChatHistoryDuration(Int)

    case burnVisitedLinksDuration(Int)

    case burnVisitsError(Error)
    case burnVisitsDuration(Int)
    case burnVisitsHasResidue

    case burnLastSessionStateError(Error)
    case burnLastSessionStateDuration(Int)
    case burnLastSessionStateHasResidue

    case burnTabsError(Error)
    case burnTabsDuration(entity: String, duration: Int)
    case burnTabsHasResidue(entity: String)

    case burnDownloadsError(Error)
    case burnDownloadsDuration(Int)
    case burnDownloadsHasResidue

    case burnRecentlyClosedDuration(Int)
    case burnRecentlyClosedHasResidue
}

// MARK: - PixelKitEvent Protocol

extension DataClearingPixels: PixelKitEvent {

    var name: String {
        switch self {
        case .fireCompletion:
            return "m_mac_fire_completion"
        case .retriggerIn20s:
            return "m_mac_fire_retrigger_in_20s"

        case .burnWebCacheError:
            return "m_mac_fire_burn_web_cache_error"
        case .burnWebCacheDuration:
            return "m_mac_fire_burn_web_cache_duration"
        case .burnWebCacheHasResidue:
            return "m_mac_fire_burn_web_cache_has_residue"

        case .burnHistoryError:
            return "m_mac_fire_burn_history_error"
        case .burnHistoryDuration:
            return "m_mac_fire_burn_history_duration"

        case .burnChatHistoryError:
            return "m_mac_fire_burn_chat_history_error"
        case .burnChatHistoryDuration:
            return "m_mac_fire_burn_chat_history_duration"

        case .burnVisitedLinksDuration:
            return "m_mac_fire_burn_visited_links_duration"

        case .burnVisitsError:
            return "m_mac_fire_burn_visits_error"
        case .burnVisitsDuration:
            return "m_mac_fire_burn_visits_duration"
        case .burnVisitsHasResidue:
            return "m_mac_fire_burn_visits_has_residue"

        case .burnLastSessionStateError:
            return "m_mac_fire_burn_last_session_state_error"
        case .burnLastSessionStateDuration:
            return "m_mac_fire_burn_last_session_state_duration"
        case .burnLastSessionStateHasResidue:
            return "m_mac_fire_burn_last_session_state_has_residue"

        case .burnTabsError:
            return "m_mac_fire_burn_tabs_error"
        case .burnTabsDuration:
            return "m_mac_fire_burn_tabs_duration"
        case .burnTabsHasResidue:
            return "m_mac_fire_burn_tabs_has_residue"

        case .burnDownloadsError:
            return "m_mac_fire_burn_downloads_error"
        case .burnDownloadsDuration:
            return "m_mac_fire_burn_downloads_duration"
        case .burnDownloadsHasResidue:
            return "m_mac_fire_burn_downloads_has_residue"

        case .burnRecentlyClosedDuration:
            return "m_mac_fire_burn_recently_closed_duration"
        case .burnRecentlyClosedHasResidue:
            return "m_mac_fire_burn_recently_closed_has_residue"
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .fireCompletion(let duration, let option, let domains, let path, let autoClear):
            return [
                "duration": String(duration),
                "clearing_option": option,
                "domains": domains,
                "path": path,
                "autoClear": autoClear
            ]

        case .burnWebCacheDuration(let duration),
             .burnChatHistoryDuration(let duration),
             .burnDownloadsDuration(let duration),
             .burnRecentlyClosedDuration(let duration),
             .burnVisitedLinksDuration(let duration),
             .burnVisitsDuration(let duration),
             .burnLastSessionStateDuration(let duration):
            return ["duration": String(duration)]

        case .burnTabsHasResidue(let entity):
            return ["entity": entity]

        case .burnHistoryDuration(let entity, let duration),
             .burnTabsDuration(let entity, let duration):
            return ["entity": entity, "duration": String(duration)]

        case .burnWebCacheHasResidue(let steps):
            return ["step": steps]

        case .retriggerIn20s,
             .burnWebCacheError, .burnHistoryError, .burnChatHistoryError,
             .burnVisitsError, .burnLastSessionStateError, .burnTabsError, .burnDownloadsError,
             .burnVisitsHasResidue, .burnLastSessionStateHasResidue,
             .burnDownloadsHasResidue, .burnRecentlyClosedHasResidue:
            return nil
        }
    }

    var error: NSError? {
        switch self {
        case .burnWebCacheError(let error),
             .burnHistoryError(let error),
             .burnChatHistoryError(let error),
             .burnVisitsError(let error),
             .burnLastSessionStateError(let error),
             .burnTabsError(let error),
             .burnDownloadsError(let error):
            return error as NSError
        default:
            return nil
        }
    }

    var standardParameters: [PixelKitStandardParameter]? {
        return [.pixelSource]
    }
}
