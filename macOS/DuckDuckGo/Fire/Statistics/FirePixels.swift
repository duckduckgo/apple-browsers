import Foundation
import PixelKit

enum FirePixels {
    
    // Overall Flow Metrics
    
    /// Fire completed
    case fireCompletion(duration: Int, option: String, domains: String, path: String, autoClear: String)
    
    /// Fire button retriggered within 20 seconds
    case retriggerIn20s
    
    // Per-Action Quality Metrics

    case burnWebCacheError(Error)
    case burnWebCacheDuration(duration: Int)
    case burnWebCacheHasResidue(String)
    
    case burnHistoryError(error: Error)
    case burnHistoryDuration(entity: String, duration: Int)
    case burnHistoryHasResidue
    
    case burnChatHistoryError(Error)
    case burnChatHistoryDuration(Int)
    case burnChatHistoryHasResidue
    
    case burnVisitedLinksError(Error)
    case burnVisitedLinksDuration(Int)
    case burnVisitedLinksHasResidue
    
    case burnVisitsError(Error)
    case burnVisitsDuration(Int)
    case burnVisitsHasResidue
    
    case burnLastSessionStateError(Error)
    case burnLastSessionStateDuration(Int)
    case burnLastSessionStateHasResidue
    
    case burnTabsError(Error)
    case burnTabsDuration(entity: String, duration: Int)
    case burnTabsHasResidue
    
    case burnDownloadsError(Error)
    case burnDownloadsDuration(duration: Int)
    case burnDownloadsHasResidue
    
    case burnRecentlyClosedError(Error)
    case burnRecentlyClosedDuration(duration: Int)
    case burnRecentlyClosedHasResidue
    
    // Retrigger Timer

    private static var retriggerTimer: Timer?
    private static let retriggerWindow: TimeInterval = 20.0
    private static var isWithinRetriggerWindow = false
}

// MARK: - Overall Flow Measurement

extension FirePixels {
    
    static func measureCompletion(from startTime: Date, dialogResult: FireDialogResult, path: FirePixels.BurnPath, autoClear: Bool) {
        PixelKit.fire(
            FirePixels.fireCompletion(
                duration: prepareDuration(from: startTime, to: Date()),
                option: prepareOptionString(dialogResult.clearingOption),
                domains: prepareDomainsString(dialogResult),
                path: preparePathString(path),
                autoClear: String(autoClear)
            )
        )
    }
    
    // Retrigger Measurement
    static func startRetriggerTimer() {
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
}

// MARK: - Per-Action Quality Metrics

extension FirePixels {
    
    
    // Duration
    
    static func measure(with durationPixel: @escaping (Int) -> FirePixels, from startTime: Date, to endTime: Date = Date()) {
        PixelKit.fire(
            durationPixel(prepareDuration(from: startTime, to: endTime))
        )
    }
    
    static func measure(with durationPixel: @escaping (String, Int) -> FirePixels, from startTime: Date, to endTime: Date = Date(), entity: String) {
        PixelKit.fire(
            durationPixel(entity, prepareDuration(from: startTime, to: endTime))
        )
    }
    
    // Effectiveness
    
    static func measure(with residuePixel: FirePixels, recheck: () -> Bool) {
        let hasResidue = recheck()
        if hasResidue {
            PixelKit.fire(residuePixel, frequency: .standard)
        }
    }
    
    static func measure(with residuePixel: @escaping (String) -> FirePixels, stepsWithResidue: String) {
        PixelKit.fire(residuePixel(stepsWithResidue), frequency: .standard)
    }
    

    // Error
    
    static func measure(with errorPixel: FirePixels) {
        PixelKit.fire(
            errorPixel
        )
    }
    
}

// MARK: - Measurement Helpers

extension FirePixels {
    
    enum BurnPath: String {
        case burnEntity = "burn_entity"
        case burnAll = "burn_all"
        case burnVisits =  "burn_visits"
    }
    
    private static func prepareDuration(from startTime: Date, to endTime: Date) -> Int {
        return Int(endTime.timeIntervalSince(startTime) * 1000)
    }
    
    /// Computes the domains array from FireDialogResult
    private static func prepareDomainsString(_ result: FireDialogResult) -> String {
        var domains: [String] = []
        if result.includeHistory {
            domains.append("History")
        }
        if result.includeTabsAndWindows {
            domains.append("TabsAndWindows")
        }
        if result.includeCookiesAndSiteData {
            domains.append("CookiesAndSiteData")
        }
        if result.includeChatHistory {
            domains.append("ChatHistory")
        }
        return domains.joined(separator: ",")
    }
    
    /// Converts ClearingOption to string for pixel
    private static func prepareOptionString(_ option: FireDialogViewModel.ClearingOption) -> String {
        return option.string
    }
    
    private static func preparePathString(_ path: FirePixels.BurnPath) -> String {
        return path.rawValue
    }
}

// MARK: - PixelKitEvent Protocol

extension FirePixels: PixelKitEvent {
    
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
        case .burnHistoryHasResidue:
            return "m_mac_fire_burn_history_has_residue"
            
        case .burnChatHistoryError:
            return "m_mac_fire_burn_chat_history_error"
        case .burnChatHistoryDuration:
            return "m_mac_fire_burn_chat_history_duration"
        case .burnChatHistoryHasResidue:
            return "m_mac_fire_burn_chat_history_has_residue"
            
        case .burnVisitedLinksError:
            return "m_mac_fire_burn_visited_links_error"
        case .burnVisitedLinksDuration:
            return "m_mac_fire_burn_visited_links_duration"
        case .burnVisitedLinksHasResidue:
            return "m_mac_fire_burn_visited_links_has_residue"
            
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
            
        case .burnRecentlyClosedError:
            return "m_mac_fire_burn_recently_closed_error"
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
            
        case .retriggerIn20s:
            return nil
            
        case .burnWebCacheDuration(let duration),
            .burnChatHistoryDuration(let duration),
            .burnDownloadsDuration(let duration),
            .burnRecentlyClosedDuration(let duration),
             .burnVisitedLinksDuration(let duration),
             .burnVisitsDuration(let duration),
             .burnLastSessionStateDuration(let duration):
            return ["duration": String(duration)]
        
        case .burnHistoryDuration(let entity, let duration),
            .burnTabsDuration(let entity, let duration):
            return ["entity": entity, "duration": String(duration)]
            
        case .burnWebCacheHasResidue(let steps):
            return ["step": steps]
            
        case .burnWebCacheError, .burnHistoryError, .burnChatHistoryError,
             .burnVisitedLinksError, .burnVisitsError, .burnLastSessionStateError,
             .burnTabsError, .burnDownloadsError, .burnRecentlyClosedError,
             .burnHistoryHasResidue, .burnChatHistoryHasResidue,
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
    
    var standardParameters: [PixelKitStandardParameter]? {
        return [.pixelSource]
    }
}
