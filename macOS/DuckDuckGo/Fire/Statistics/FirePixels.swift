//
//  FirePixels.swift
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

enum FirePixels {
    
    // MARK: - Overall Flow Metrics
    
    /// Clearing completed - total fire operation duration
    case clearingCompletion(duration: Int)  // milliseconds
    
    /// Fire button retriggered within 20 seconds
    case retriggerIn20s
    
    // MARK: - Per-Action Quality Metrics (3 per action: Error, Duration, HasResidue)
    
    // burnWebCache
    case burnWebCacheError(Error)
    case burnWebCacheDuration(Int)
    case burnWebCacheHasResidue
    
    // burnHistory
    case burnHistoryError(Error)
    case burnHistoryDuration(Int)
    case burnHistoryHasResidue
    
    // burnChatHistory
    case burnChatHistoryError(Error)
    case burnChatHistoryDuration(Int)
    case burnChatHistoryHasResidue
    
    // burnVisitedLinks
    case burnVisitedLinksError(Error)
    case burnVisitedLinksDuration(Int)
    case burnVisitedLinksHasResidue
    
    // burnVisits
    case burnVisitsError(Error)
    case burnVisitsDuration(Int)
    case burnVisitsHasResidue
    
    // burnLastSessionState
    case burnLastSessionStateError(Error)
    case burnLastSessionStateDuration(Int)
    case burnLastSessionStateHasResidue
    
    // burnTabs
    case burnTabsError(Error)
    case burnTabsDuration(Int)
    case burnTabsHasResidue
    
    // burnDownloads
    case burnDownloadsError(Error)
    case burnDownloadsDuration(Int)
    case burnDownloadsHasResidue
    
    // burnRecentlyClosed
    case burnRecentlyClosedError(Error)
    case burnRecentlyClosedDuration(Int)
    case burnRecentlyClosedHasResidue
    
    // Retrigger Timer
    private static var retriggerTimer: Timer?
    private static let retriggerWindow: TimeInterval = 20.0
    private static var isWithinRetriggerWindow = false
}


// MARK: - Measurement Helpers

extension FirePixels {
    
    // Retrigger Timer
    
    /// Starts the 20-second retrigger detection window
    static func startRetriggerTimer() {
        // If timer is active, fire retrigger pixel
        if isWithinRetriggerWindow {
            PixelKit.fire(FirePixels.retriggerIn20s, frequency: .standard)
        }
        
        // Invalidate existing timer and start new one
        retriggerTimer?.invalidate()
        isWithinRetriggerWindow = true
        
        retriggerTimer = Timer.scheduledTimer(withTimeInterval: retriggerWindow, repeats: false) { _ in
            isWithinRetriggerWindow = false
        }
    }
    
    // Duration Measurement Helper
    
    /// Measures execution time and automatically fires the duration pixel
    /// - Parameters:
    ///   - durationPixel: A closure that takes duration in milliseconds and returns the appropriate FirePixels duration case
    ///   - operation: The operation to measure and execute
    /// - Throws: Rethrows any error from the operation
    /// - Returns: The result of the operation
    @discardableResult
    static func measured<T>(
        _ durationPixel: @escaping (Int) -> FirePixels,
        operation: () async throws -> T
    ) async rethrows -> T {
        let startTime = Date()
        do {
            let result = try await operation()
            let duration = Int(Date().timeIntervalSince(startTime) * 1000)
            PixelKit.fire(durationPixel(duration), frequency: .standard)
            return result
        } catch {
            let duration = Int(Date().timeIntervalSince(startTime) * 1000)
            PixelKit.fire(durationPixel(duration), frequency: .standard)
            throw error
        }
    }
    
    /// Synchronous variant for non-async operations
    @discardableResult
    static func measured<T>(
        _ durationPixel: @escaping (Int) -> FirePixels,
        operation: () throws -> T
    ) rethrows -> T {
        let startTime = Date()
        do {
            let result = try operation()
            let duration = Int(Date().timeIntervalSince(startTime) * 1000)
            PixelKit.fire(durationPixel(duration), frequency: .standard)
            return result
        } catch {
            let duration = Int(Date().timeIntervalSince(startTime) * 1000)
            PixelKit.fire(durationPixel(duration), frequency: .standard)
            throw error
        }
    }
    
    // Residue Detection
    
    /// Checks for residual data and automatically fires the residue pixel if found
    /// - Parameters:
    ///   - residuePixel: The residue pixel to fire if residual data is detected
    ///   - check: Closure that performs the residue check, returns true if residue exists
    static func checkResidue(
        _ residuePixel: FirePixels,
        check: () async -> Bool
    ) async {
        let hasResidue = await check()
        if hasResidue {
            PixelKit.fire(residuePixel, frequency: .standard)
        }
    }
    
    /// Synchronous variant for non-async residue checks
    static func checkResidue(
        _ residuePixel: FirePixels,
        check: () -> Bool
    ) {
        let hasResidue = check()
        if hasResidue {
            PixelKit.fire(residuePixel, frequency: .standard)
        }
    }
    
}

// MARK: - PixelKitEvent Protocol

extension FirePixels: PixelKitEvent {
    
    var name: String {
        switch self {
        case .clearingCompletion:
            return "m_mac_fire_completion"
        case .retriggerIn20s:
            return "m_mac_fire_retrigger_in_20s"
            
        // burnWebCache
        case .burnWebCacheError:
            return "m_mac_fire_burn_web_cache_error"
        case .burnWebCacheDuration:
            return "m_mac_fire_burn_web_cache_duration"
        case .burnWebCacheHasResidue:
            return "m_mac_fire_burn_web_cache_has_residue"
            
        // burnHistory
        case .burnHistoryError:
            return "m_mac_fire_burn_history_error"
        case .burnHistoryDuration:
            return "m_mac_fire_burn_history_duration"
        case .burnHistoryHasResidue:
            return "m_mac_fire_burn_history_has_residue"
            
        // burnChatHistory
        case .burnChatHistoryError:
            return "m_mac_fire_burn_chat_history_error"
        case .burnChatHistoryDuration:
            return "m_mac_fire_burn_chat_history_duration"
        case .burnChatHistoryHasResidue:
            return "m_mac_fire_burn_chat_history_has_residue"
            
        // burnVisitedLinks
        case .burnVisitedLinksError:
            return "m_mac_fire_burn_visited_links_error"
        case .burnVisitedLinksDuration:
            return "m_mac_fire_burn_visited_links_duration"
        case .burnVisitedLinksHasResidue:
            return "m_mac_fire_burn_visited_links_has_residue"
            
        // burnVisits
        case .burnVisitsError:
            return "m_mac_fire_burn_visits_error"
        case .burnVisitsDuration:
            return "m_mac_fire_burn_visits_duration"
        case .burnVisitsHasResidue:
            return "m_mac_fire_burn_visits_has_residue"
            
        // burnLastSessionState
        case .burnLastSessionStateError:
            return "m_mac_fire_burn_last_session_state_error"
        case .burnLastSessionStateDuration:
            return "m_mac_fire_burn_last_session_state_duration"
        case .burnLastSessionStateHasResidue:
            return "m_mac_fire_burn_last_session_state_has_residue"
            
        // burnTabs
        case .burnTabsError:
            return "m_mac_fire_burn_tabs_error"
        case .burnTabsDuration:
            return "m_mac_fire_burn_tabs_duration"
        case .burnTabsHasResidue:
            return "m_mac_fire_burn_tabs_has_residue"
            
        // burnDownloads
        case .burnDownloadsError:
            return "m_mac_fire_burn_downloads_error"
        case .burnDownloadsDuration:
            return "m_mac_fire_burn_downloads_duration"
        case .burnDownloadsHasResidue:
            return "m_mac_fire_burn_downloads_has_residue"
            
        // burnRecentlyClosed
        case .burnRecentlyClosedError:
            return "m_mac_fire_burn_recently_closed_error"
        case .burnRecentlyClosedDuration:
            return "m_mac_fire_burn_recently_closed_duration"
        case .burnRecentlyClosedHasResidue:
            return "m_mac_fire_burn_recently_closed_has_residue"
        }
    }
    
    
    var standardParameters: [PixelKitStandardParameter]? {
        return [.pixelSource]
    }
    
    var parameters: [String: String]? {
        switch self {
        case .clearingCompletion(let duration):
            return ["duration": String(duration)]
            
        case .retriggerIn20s:
            return nil
            
        // Duration pixels (all 9 actions have duration)
        case .burnWebCacheDuration(let ms),
             .burnHistoryDuration(let ms),
             .burnChatHistoryDuration(let ms),
             .burnVisitedLinksDuration(let ms),
             .burnVisitsDuration(let ms),
             .burnLastSessionStateDuration(let ms),
             .burnTabsDuration(let ms),
             .burnDownloadsDuration(let ms),
             .burnRecentlyClosedDuration(let ms):
            return ["duration": String(ms)]
            
        // All other pixels have no parameters (error auto-extracted, residue is count only)
        case .burnWebCacheError, .burnHistoryError, .burnChatHistoryError,
             .burnVisitedLinksError, .burnVisitsError, .burnLastSessionStateError,
             .burnTabsError, .burnDownloadsError, .burnRecentlyClosedError,
             .burnWebCacheHasResidue, .burnHistoryHasResidue, .burnChatHistoryHasResidue,
             .burnVisitedLinksHasResidue, .burnVisitsHasResidue, .burnLastSessionStateHasResidue,
             .burnTabsHasResidue, .burnDownloadsHasResidue, .burnRecentlyClosedHasResidue:
            return nil
        }
    }
    
    var error: NSError? {
        switch self {
        case .burnWebCacheError(let error),
             .burnHistoryError(let error),
             .burnChatHistoryError(let error),
             .burnVisitedLinksError(let error),
             .burnVisitsError(let error),
             .burnLastSessionStateError(let error),
             .burnTabsError(let error),
             .burnDownloadsError(let error),
             .burnRecentlyClosedError(let error):
            return error as NSError
        default:
            return nil
        }
    }
}
