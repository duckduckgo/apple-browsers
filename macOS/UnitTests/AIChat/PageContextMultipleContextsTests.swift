//
//  PageContextMultipleContextsTests.swift
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

import AIChat
import Foundation
import Testing

@testable import DuckDuckGo_Privacy_Browser

// MARK: - NavigationContextAction Tests

struct NavigationContextActionTests {

    /// Helper that mirrors the logic in PageContextTabExtension.navigationAction
    private func navigationAction(autoCollectEnabled: Bool, contextConsumed: Bool, fromAttachablePage: Bool = true) -> String {
        if autoCollectEnabled {
            return "collectNewContext"
        } else if contextConsumed || !fromAttachablePage {
            return "sendNavigationSignal"
        } else {
            return "keepExistingContext"
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("Auto-collect ON returns collectNewContext regardless of consumed state", .timeLimit(.minutes(1)))
    func autoCollectOnCollectsNewContext() {
        #expect(navigationAction(autoCollectEnabled: true, contextConsumed: false) == "collectNewContext")
        #expect(navigationAction(autoCollectEnabled: true, contextConsumed: true) == "collectNewContext")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Auto-collect OFF with consumed context returns sendNavigationSignal", .timeLimit(.minutes(1)))
    func autoCollectOffConsumedSendsSignal() {
        #expect(navigationAction(autoCollectEnabled: false, contextConsumed: true) == "sendNavigationSignal")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Auto-collect OFF without consumed context returns keepExistingContext", .timeLimit(.minutes(1)))
    func autoCollectOffNotConsumedKeeps() {
        #expect(navigationAction(autoCollectEnabled: false, contextConsumed: false) == "keepExistingContext")
    }

    // fromAttachablePage = false (navigating FROM NTP/settings/etc. to a URL)

    @available(iOS 16, macOS 13, *)
    @Test("NTP to URL with auto-collect OFF and no prior chat sends navigation signal", .timeLimit(.minutes(1)))
    func ntpToURLAutoCollectOffNoChat() {
        #expect(navigationAction(autoCollectEnabled: false, contextConsumed: false, fromAttachablePage: false) == "sendNavigationSignal")
    }

    @available(iOS 16, macOS 13, *)
    @Test("NTP to URL with auto-collect ON collects new context", .timeLimit(.minutes(1)))
    func ntpToURLAutoCollectOn() {
        #expect(navigationAction(autoCollectEnabled: true, contextConsumed: false, fromAttachablePage: false) == "collectNewContext")
    }

    @available(iOS 16, macOS 13, *)
    @Test("NTP to URL with consumed context sends navigation signal", .timeLimit(.minutes(1)))
    func ntpToURLContextConsumed() {
        #expect(navigationAction(autoCollectEnabled: false, contextConsumed: true, fromAttachablePage: false) == "sendNavigationSignal")
    }
}

// MARK: - isContextCollectionEnabled Logic Tests

struct ContextCollectionEnabledTests {

    /// Mirrors the logic in PageContextTabExtension.isContextCollectionEnabled
    private func isContextCollectionEnabled(
        shouldForceContextCollection: Bool,
        userRemovedContext: Bool,
        shouldAutomaticallySendPageContext: Bool
    ) -> Bool {
        if shouldForceContextCollection { return true }
        if userRemovedContext { return false }
        return shouldAutomaticallySendPageContext
    }

    @available(iOS 16, macOS 13, *)
    @Test("Force collection overrides everything", .timeLimit(.minutes(1)))
    func forceCollectionOverrides() {
        #expect(isContextCollectionEnabled(shouldForceContextCollection: true, userRemovedContext: true, shouldAutomaticallySendPageContext: false) == true)
        #expect(isContextCollectionEnabled(shouldForceContextCollection: true, userRemovedContext: false, shouldAutomaticallySendPageContext: false) == true)
    }

    @available(iOS 16, macOS 13, *)
    @Test("User removed context suppresses auto-collection", .timeLimit(.minutes(1)))
    func userRemovedSuppresses() {
        #expect(isContextCollectionEnabled(shouldForceContextCollection: false, userRemovedContext: true, shouldAutomaticallySendPageContext: true) == false)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Auto-send setting is respected when no overrides", .timeLimit(.minutes(1)))
    func autoSendRespected() {
        #expect(isContextCollectionEnabled(shouldForceContextCollection: false, userRemovedContext: false, shouldAutomaticallySendPageContext: true) == true)
        #expect(isContextCollectionEnabled(shouldForceContextCollection: false, userRemovedContext: false, shouldAutomaticallySendPageContext: false) == false)
    }
}

// MARK: - hasContextBeenConsumedByChat Reset Tests

struct ConsumedFlagResetTests {

    /// Mirrors the reset logic in PageContextTabExtension.handle()
    private func shouldResetConsumedFlag(pageContext: AIChatPageContextData?) -> Bool {
        pageContext != nil && pageContext?.attachable != false
    }

    @available(iOS 16, macOS 13, *)
    @Test("Attachable context resets consumed flag", .timeLimit(.minutes(1)))
    func attachableContextResets() {
        let context = AIChatPageContextData(title: "Test", favicon: [], url: "https://example.com", content: "content", truncated: false, fullContentLength: 100)
        #expect(shouldResetConsumedFlag(pageContext: context) == true)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Non-attachable context does not reset consumed flag", .timeLimit(.minutes(1)))
    func nonAttachableDoesNotReset() {
        let context = AIChatPageContextData(title: "NTP", favicon: [], url: "", content: "", truncated: false, fullContentLength: 0, attachable: false)
        #expect(shouldResetConsumedFlag(pageContext: context) == false)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Nil context does not reset consumed flag", .timeLimit(.minutes(1)))
    func nilDoesNotReset() {
        #expect(shouldResetConsumedFlag(pageContext: nil) == false)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Context with attachable=true resets consumed flag", .timeLimit(.minutes(1)))
    func explicitlyAttachableResets() {
        let context = AIChatPageContextData(title: "Test", favicon: [], url: "https://example.com", content: "content", truncated: false, fullContentLength: 100, attachable: true)
        #expect(shouldResetConsumedFlag(pageContext: context) == true)
    }
}

// MARK: - Selection Context ("Attach to Duck.ai") Tests

struct SelectionContextTests {

    /// Mirrors `AIChatSelectionContextAttacher.Constants.maxSelectionContextLength`.
    private static let maxSelectionContextLength = 9500

    /// Mirrors `AIChatSelectionContextAttacher` payload construction.
    private func buildSelectionItem(text: String, url: String) -> AIChatSelectionContextData {
        let truncated = text.count > Self.maxSelectionContextLength
        let content = truncated ? String(text.prefix(Self.maxSelectionContextLength)) : text
        return AIChatSelectionContextData(
            id: UUID().uuidString,
            title: "Text selection",
            url: url,
            content: content,
            truncated: truncated,
            fullContentLength: text.count,
            wordCount: text.split(whereSeparator: \.isWhitespace).count
        )
    }

    @available(iOS 16, macOS 13, *)
    @Test("Short selection carries the generic title and is not truncated", .timeLimit(.minutes(1)))
    func shortSelectionIsTaggedAndNotTruncated() {
        let item = buildSelectionItem(text: "hello world", url: "https://example.com")
        #expect(item.content == "hello world")
        #expect(item.title == "Text selection")
        #expect(item.url == "https://example.com")
        #expect(item.truncated == false)
        #expect(item.fullContentLength == 11)
        #expect(item.wordCount == 2)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Word count covers the full selection even when truncated", .timeLimit(.minutes(1)))
    func wordCountReflectsFullSelection() {
        // 6000 two-char words separated by spaces → 11999 chars, truncated at 9500, but wordCount is the full 6000.
        let longText = Array(repeating: "ab", count: 6000).joined(separator: " ")
        let item = buildSelectionItem(text: longText, url: "https://example.com")
        #expect(item.truncated == true)
        #expect(item.wordCount == 6000)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Long selection is truncated to the max length and reports the original length", .timeLimit(.minutes(1)))
    func longSelectionIsTruncated() {
        let longText = String(repeating: "x", count: Self.maxSelectionContextLength + 500)
        let item = buildSelectionItem(text: longText, url: "https://example.com")
        #expect(item.content.count == Self.maxSelectionContextLength)
        #expect(item.truncated == true)
        #expect(item.fullContentLength == longText.count)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Each attached selection gets a unique id", .timeLimit(.minutes(1)))
    func eachSelectionHasUniqueID() {
        let first = buildSelectionItem(text: "a", url: "https://example.com")
        let second = buildSelectionItem(text: "a", url: "https://example.com")
        #expect(first.id != second.id)
    }
}

// MARK: - Per-navigation extraction pixel dedup Tests

struct PerNavigationExtractionPixelDedupTests {

    /// Mirrors the per-navigation dedup in PageContextTabExtension.fireExtractionPixel: automatic
    /// page-load collects (.navigation / .tabContent) report once per navigation and re-arm on
    /// navigation to a new URL; user/setting collects (.userRequest / .auto) always report.
    private final class Dedup {
        private var didReportForCurrentNavigation = false

        func resetForNavigation() { didReportForCurrentNavigation = false }

        func shouldReport(_ trigger: PageContextExtractionTrigger) -> Bool {
            guard trigger == .navigation || trigger == .tabContent else { return true }
            if didReportForCurrentNavigation { return false }
            didReportForCurrentNavigation = true
            return true
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("First automatic collect reports; the navigation's later automatic collects are suppressed", .timeLimit(.minutes(1)))
    func firstAutomaticReportsRestSuppressed() {
        let dedup = Dedup()
        #expect(dedup.shouldReport(.navigation) == true)   // didCommit re-collect
        #expect(dedup.shouldReport(.navigation) == false)  // didFinish re-collect
        #expect(dedup.shouldReport(.tabContent) == false)  // signals-only harvest
    }

    @available(iOS 16, macOS 13, *)
    @Test("navigation and tabContent share the single per-navigation slot", .timeLimit(.minutes(1)))
    func navigationAndTabContentShareSlot() {
        let dedup = Dedup()
        #expect(dedup.shouldReport(.tabContent) == true)
        #expect(dedup.shouldReport(.navigation) == false)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Navigation to a new URL re-arms automatic reporting", .timeLimit(.minutes(1)))
    func navigationResetReArms() {
        let dedup = Dedup()
        #expect(dedup.shouldReport(.navigation) == true)
        #expect(dedup.shouldReport(.navigation) == false)
        dedup.resetForNavigation()
        #expect(dedup.shouldReport(.navigation) == true)
    }

    @available(iOS 16, macOS 13, *)
    @Test("User- and setting-initiated collects always report and never consume the slot", .timeLimit(.minutes(1)))
    func userAndSettingAlwaysReport() {
        let dedup = Dedup()
        #expect(dedup.shouldReport(.userRequest) == true)
        #expect(dedup.shouldReport(.auto) == true)
        #expect(dedup.shouldReport(.userRequest) == true)
        // Slot untouched by user/setting collects, so the first automatic collect still reports.
        #expect(dedup.shouldReport(.navigation) == true)
    }
}

// MARK: - Sidebar-open extraction measurement Tests

struct SidebarOpenExtractionMeasurementTests {

    private enum Outcome: Equatable {
        case none
        case prevented(String)
        case collect
    }

    private func sidebarOpenOutcome(isURL: Bool,
                                    preventedReason: String?,
                                    isContextCollectionEnabled: Bool) -> Outcome {
        guard isURL else { return .prevented("internalPage") }
        if let preventedReason { return .prevented(preventedReason) }
        if isContextCollectionEnabled { return .collect }
        return .none
    }

    @available(iOS 16, macOS 13, *)
    @Test("Native special page (non-URL content) reports prevented(internalPage)", .timeLimit(.minutes(1)))
    func nativePageReportsInternalPagePrevented() {
        #expect(sidebarOpenOutcome(isURL: false, preventedReason: nil, isContextCollectionEnabled: true) == .prevented("internalPage"))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Non-attachable URL reports prevented with the blocklist category, no interaction needed", .timeLimit(.minutes(1)))
    func nonAttachableURLReportsPrevented() {
        #expect(sidebarOpenOutcome(isURL: true, preventedReason: "pdf", isContextCollectionEnabled: false) == .prevented("pdf"))
        #expect(sidebarOpenOutcome(isURL: true, preventedReason: "image", isContextCollectionEnabled: true) == .prevented("image"))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Attachable URL with auto-collect ON re-collects so success/failure fire live", .timeLimit(.minutes(1)))
    func attachableAutoOnReCollects() {
        #expect(sidebarOpenOutcome(isURL: true, preventedReason: nil, isContextCollectionEnabled: true) == .collect)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Attachable URL with auto-collect OFF reports nothing on open (awaits user tap / signals-only)", .timeLimit(.minutes(1)))
    func attachableAutoOffReportsNone() {
        #expect(sidebarOpenOutcome(isURL: true, preventedReason: nil, isContextCollectionEnabled: false) == .none)
    }

    private func deliversPreventedContextOnSidebarOpen(isURL: Bool, preventedReason: String?) -> Bool {
        guard isURL else { return false }
        return preventedReason != nil
    }

    @available(iOS 16, macOS 13, *)
    @Test("Non-attachable URL pushes an attachable:false context on sidebar open so the FE hides Ask-About-Page", .timeLimit(.minutes(1)))
    func nonAttachableURLDeliversPreventedContext() {
        #expect(deliversPreventedContextOnSidebarOpen(isURL: true, preventedReason: "pdf") == true)
        #expect(deliversPreventedContextOnSidebarOpen(isURL: true, preventedReason: "image") == true)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Attachable URL does not push a prevented context on sidebar open", .timeLimit(.minutes(1)))
    func attachableURLDoesNotDeliverPreventedContext() {
        #expect(deliversPreventedContextOnSidebarOpen(isURL: true, preventedReason: nil) == false)
    }

    private final class Guard {
        private var didReportExtraction = false
        private var didReportSidebarOpen = false

        func resetForNavigation() {
            didReportExtraction = false
            didReportSidebarOpen = false
        }

        func markCollectionReported() { didReportExtraction = true }

        func shouldMeasureOnSidebarOpen(isVisible: Bool, measurementEnabled: Bool) -> Bool {
            guard isVisible, measurementEnabled, !didReportExtraction, !didReportSidebarOpen else { return false }
            didReportSidebarOpen = true
            return true
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("First sidebar open measures; re-opening on the same page (kept session) does not", .timeLimit(.minutes(1)))
    func firstOpenMeasuresReopenDoesNot() {
        let guardState = Guard()
        #expect(guardState.shouldMeasureOnSidebarOpen(isVisible: true, measurementEnabled: true) == true)
        #expect(guardState.shouldMeasureOnSidebarOpen(isVisible: true, measurementEnabled: true) == false)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A collection that already reported this navigation suppresses the sidebar-open measurement", .timeLimit(.minutes(1)))
    func collectionReportSuppressesMeasurement() {
        let guardState = Guard()
        guardState.markCollectionReported()
        #expect(guardState.shouldMeasureOnSidebarOpen(isVisible: true, measurementEnabled: true) == false)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Navigation to a new URL re-arms the sidebar-open measurement", .timeLimit(.minutes(1)))
    func navigationReArmsMeasurement() {
        let guardState = Guard()
        #expect(guardState.shouldMeasureOnSidebarOpen(isVisible: true, measurementEnabled: true) == true)
        guardState.resetForNavigation()
        #expect(guardState.shouldMeasureOnSidebarOpen(isVisible: true, measurementEnabled: true) == true)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A hidden sidebar or absent blocklist config never measures and never consumes the slot", .timeLimit(.minutes(1)))
    func hiddenOrDisabledDoesNotConsumeSlot() {
        let guardState = Guard()
        #expect(guardState.shouldMeasureOnSidebarOpen(isVisible: false, measurementEnabled: true) == false)
        #expect(guardState.shouldMeasureOnSidebarOpen(isVisible: true, measurementEnabled: false) == false)
        #expect(guardState.shouldMeasureOnSidebarOpen(isVisible: true, measurementEnabled: true) == true)
    }
}

// MARK: - Collection-result extraction measurement Tests

struct CollectionResultExtractionMeasurementTests {

    private func firesExtractionOutcome(isContextCollectionEnabled: Bool, pendingSignalsOnly: Bool) -> Bool {
        if isContextCollectionEnabled { return true }
        if pendingSignalsOnly { return false }
        return false
    }

    @available(iOS 16, macOS 13, *)
    @Test("Full collection (auto-attach on / user-forced) reports its extraction outcome", .timeLimit(.minutes(1)))
    func fullCollectionReports() {
        #expect(firesExtractionOutcome(isContextCollectionEnabled: true, pendingSignalsOnly: false) == true)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Signals-only harvest does not report success/failed", .timeLimit(.minutes(1)))
    func signalsOnlyDoesNotReport() {
        #expect(firesExtractionOutcome(isContextCollectionEnabled: false, pendingSignalsOnly: true) == false)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Unsolicited collection result reports nothing", .timeLimit(.minutes(1)))
    func unsolicitedReportsNothing() {
        #expect(firesExtractionOutcome(isContextCollectionEnabled: false, pendingSignalsOnly: false) == false)
    }
}

// MARK: - Empty-content pixel suppression Tests

struct EmptyContentPixelSuppressionTests {

    /// Mirrors the guard in `fireExtractionPixel`: an empty-content failure from an automatic collect
    /// (premature / mid-redirect snapshot) is not reported; a user-requested one still is.
    private func reportsEmptyContentFailure(trigger: String) -> Bool {
        trigger == "userRequest"
    }

    @available(iOS 16, macOS 13, *)
    @Test("Empty-content failure from a navigation collect is not reported (premature / redirect noise)", .timeLimit(.minutes(1)))
    func navigationEmptyContentSuppressed() {
        #expect(reportsEmptyContentFailure(trigger: "navigation") == false)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Empty-content failure from a tabContent (signals-only) collect is not reported", .timeLimit(.minutes(1)))
    func tabContentEmptyContentSuppressed() {
        #expect(reportsEmptyContentFailure(trigger: "tabContent") == false)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Empty-content failure from an auto (sidebar-open / setting) collect is not reported", .timeLimit(.minutes(1)))
    func autoEmptyContentSuppressed() {
        #expect(reportsEmptyContentFailure(trigger: "auto") == false)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Empty-content failure from a user-requested collect is still reported", .timeLimit(.minutes(1)))
    func userRequestEmptyContentReported() {
        #expect(reportsEmptyContentFailure(trigger: "userRequest") == true)
    }
}

// MARK: - Non-attachable page context normalization Tests

struct NonAttachableNormalizationTests {

    private func effectiveAttachable(pageIsNonAttachable: Bool, contextAttachable: Bool?) -> Bool? {
        guard pageIsNonAttachable, contextAttachable != false else { return contextAttachable }
        return false
    }

    @available(iOS 16, macOS 13, *)
    @Test("Raw collected context (attachable nil) on a non-attachable page is forced to false", .timeLimit(.minutes(1)))
    func rawContextForcedFalse() {
        #expect(effectiveAttachable(pageIsNonAttachable: true, contextAttachable: nil) == false)
    }

    @available(iOS 16, macOS 13, *)
    @Test("attachable:true on a non-attachable page is forced to false", .timeLimit(.minutes(1)))
    func trueForcedFalseOnNonAttachable() {
        #expect(effectiveAttachable(pageIsNonAttachable: true, contextAttachable: true) == false)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Already-false context on a non-attachable page stays false", .timeLimit(.minutes(1)))
    func falseStaysFalse() {
        #expect(effectiveAttachable(pageIsNonAttachable: true, contextAttachable: false) == false)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Attachable page leaves attachable untouched (nil stays nil = attachable, true stays true)", .timeLimit(.minutes(1)))
    func attachablePageUntouched() {
        #expect(effectiveAttachable(pageIsNonAttachable: false, contextAttachable: nil) == nil)
        #expect(effectiveAttachable(pageIsNonAttachable: false, contextAttachable: true) == true)
    }
}

// MARK: - Main-frame MIME cache (back/forward attachability) Tests

struct MainFrameMIMECacheTests {

    private let pdfURL = URL(string: "https://arxiv.org/pdf/2602.11988")!
    private let htmlURL = URL(string: "https://en.wikipedia.org/wiki/Potato")!

    @available(iOS 16, macOS 13, *)
    @Test("MIME for a URL survives navigating away and back (unlike a last-response slot)", .timeLimit(.minutes(1)))
    func mimeSurvivesBackForward() {
        var cache = MainFrameMIMECache()
        cache.record("application/pdf", for: pdfURL)
        cache.record("text/html", for: htmlURL)
        #expect(cache[pdfURL] == "application/pdf")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Empty or nil MIME is not recorded", .timeLimit(.minutes(1)))
    func emptyMIMENotRecorded() {
        var cache = MainFrameMIMECache()
        cache.record(nil, for: htmlURL)
        cache.record("", for: htmlURL)
        #expect(cache[htmlURL] == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Cache is bounded FIFO — the oldest URL is evicted past the cap", .timeLimit(.minutes(1)))
    func boundedFIFO() {
        let urls = (1...3).map { URL(string: "https://example.com/\($0)")! }
        var cache = MainFrameMIMECache(capacity: 2)
        cache.record("a/a", for: urls[0])
        cache.record("b/b", for: urls[1])
        cache.record("c/c", for: urls[2])
        #expect(cache[urls[0]] == nil)
        #expect(cache[urls[1]] == "b/b")
        #expect(cache[urls[2]] == "c/c")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Re-recording a cached URL updates the MIME without double-counting against the cap", .timeLimit(.minutes(1)))
    func reRecordUpdatesInPlace() {
        let urls = (1...2).map { URL(string: "https://example.com/\($0)")! }
        var cache = MainFrameMIMECache(capacity: 2)
        cache.record("a/a", for: urls[0])
        cache.record("b/b", for: urls[1])
        cache.record("a/b", for: urls[0])
        #expect(cache[urls[0]] == "a/b")
        #expect(cache[urls[1]] == "b/b")
    }
}

// MARK: - Settled-navigation re-collect Tests

struct SettledNavigationReCollectTests {

    /// Mirrors `PageContextTabExtension.reCollectForSettledNavigation` + the committed-didFail hook:
    /// committed failures (back/forward -999 restores) re-collect like didFinish, only on a URL match.
    private func shouldReCollect(event: String, isCommitted: Bool, contentURL: String?, navigationURL: String) -> Bool {
        if event == "didFail" && !isCommitted { return false }
        guard let contentURL else { return false }
        return contentURL == navigationURL
    }

    @available(iOS 16, macOS 13, *)
    @Test("didFinish with settled content re-collects", .timeLimit(.minutes(1)))
    func didFinishSettledReCollects() {
        #expect(shouldReCollect(event: "didFinish", isCommitted: true, contentURL: "https://a.com", navigationURL: "https://a.com") == true)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Committed didFail (back/forward cache restore, -999) re-collects like didFinish", .timeLimit(.minutes(1)))
    func committedDidFailReCollects() {
        #expect(shouldReCollect(event: "didFail", isCommitted: true, contentURL: "https://a.com", navigationURL: "https://a.com") == true)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Uncommitted didFail (real load failure, nothing displayed) does not re-collect", .timeLimit(.minutes(1)))
    func uncommittedDidFailSkips() {
        #expect(shouldReCollect(event: "didFail", isCommitted: false, contentURL: "https://a.com", navigationURL: "https://a.com") == false)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Stale debounced content (previous page's URL) skips the re-collect", .timeLimit(.minutes(1)))
    func staleContentSkips() {
        #expect(shouldReCollect(event: "didFinish", isCommitted: true, contentURL: "https://old.com", navigationURL: "https://new.com") == false)
        #expect(shouldReCollect(event: "didFail", isCommitted: true, contentURL: "https://old.com", navigationURL: "https://new.com") == false)
    }

    /// Mirrors the document-match guard in `collectPageContextIfNeeded`: automatic collects only run
    /// when the webview is displaying the page being gated on; user collects always proceed.
    private func shouldRunAutomaticCollect(trigger: String, webViewURL: String?, contentURL: String) -> Bool {
        guard trigger == "navigation" || trigger == "tabContent" else { return true }
        guard let webViewURL else { return true }
        return webViewURL == contentURL
    }

    @available(iOS 16, macOS 13, *)
    @Test("Automatic collect is skipped while the webview still displays the previous document", .timeLimit(.minutes(1)))
    func automaticCollectSkippedOnDocumentMismatch() {
        #expect(shouldRunAutomaticCollect(trigger: "navigation", webViewURL: "https://old.com", contentURL: "https://new.com") == false)
        #expect(shouldRunAutomaticCollect(trigger: "tabContent", webViewURL: "https://old.com", contentURL: "https://new.com") == false)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Automatic collect proceeds when webview and content agree", .timeLimit(.minutes(1)))
    func automaticCollectProceedsOnMatch() {
        #expect(shouldRunAutomaticCollect(trigger: "navigation", webViewURL: "https://a.com", contentURL: "https://a.com") == true)
    }

    @available(iOS 16, macOS 13, *)
    @Test("User-initiated collect proceeds regardless of document mismatch", .timeLimit(.minutes(1)))
    func userCollectAlwaysProceeds() {
        #expect(shouldRunAutomaticCollect(trigger: "userRequest", webViewURL: "https://old.com", contentURL: "https://new.com") == true)
    }

    /// Mirrors `runPendingSettledNavigationReCollectIfNeeded`: a settled navigation whose URL the
    /// debounced content hasn't caught up to is latched, then re-collected once content matches —
    /// unless a collect is already in flight (the multi-contexts path already covered it).
    private func runsDeferredReCollect(latchedURL: String?, settledContentURL: String, hasPendingCollections: Bool) -> Bool {
        guard let latchedURL, latchedURL == settledContentURL else { return false }
        return !hasPendingCollections
    }

    @available(iOS 16, macOS 13, *)
    @Test("Deferred settled navigation re-collects once content catches up", .timeLimit(.minutes(1)))
    func deferredReCollectFiresWhenContentSettles() {
        #expect(runsDeferredReCollect(latchedURL: "https://a.com", settledContentURL: "https://a.com", hasPendingCollections: false) == true)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Deferred re-collect is skipped when a collect is already in flight (multi-contexts path covered it)", .timeLimit(.minutes(1)))
    func deferredReCollectSkippedWhenCollectInFlight() {
        #expect(runsDeferredReCollect(latchedURL: "https://a.com", settledContentURL: "https://a.com", hasPendingCollections: true) == false)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Deferred re-collect for a superseded navigation (content settled on another URL) does not fire", .timeLimit(.minutes(1)))
    func deferredReCollectSkippedWhenSuperseded() {
        #expect(runsDeferredReCollect(latchedURL: "https://a.com", settledContentURL: "https://b.com", hasPendingCollections: false) == false)
    }

    @available(iOS 16, macOS 13, *)
    @Test("No latched navigation means no deferred re-collect", .timeLimit(.minutes(1)))
    func noLatchNoDeferredReCollect() {
        #expect(runsDeferredReCollect(latchedURL: nil, settledContentURL: "https://a.com", hasPendingCollections: false) == false)
    }
}

// MARK: - Collection result delivery

/// `PageContextTabExtension.shouldDeliverCollectionResult`: which collection results reach
/// `handle()`. A forced (user-requested) collect must resolve even when empty — the FE awaits
/// the `getAIChatPageContext` response — but must never replace attached content.
struct PageContextCollectionResultDeliveryTests {

    private func context(content: String) -> AIChatPageContextData {
        AIChatPageContextData(title: "Title", favicon: [], url: "https://example.com", content: content, truncated: false, fullContentLength: content.count)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A result with content is always delivered", .timeLimit(.minutes(1)))
    func resultWithContentIsDelivered() {
        #expect(PageContextTabExtension.shouldDeliverCollectionResult(context(content: "body"), wasForced: false, cached: nil))
        #expect(PageContextTabExtension.shouldDeliverCollectionResult(context(content: "body"), wasForced: true, cached: context(content: "old")))
    }

    @available(iOS 16, macOS 13, *)
    @Test("An unsolicited empty or nil result is dropped", .timeLimit(.minutes(1)))
    func unforcedEmptyResultIsDropped() {
        #expect(!PageContextTabExtension.shouldDeliverCollectionResult(context(content: ""), wasForced: false, cached: nil))
        #expect(!PageContextTabExtension.shouldDeliverCollectionResult(nil, wasForced: false, cached: nil))
    }

    @available(iOS 16, macOS 13, *)
    @Test("A forced empty result is delivered when nothing with content is attached, so the awaiting FE request resolves", .timeLimit(.minutes(1)))
    func forcedEmptyResultIsDeliveredWhenNothingAttached() {
        #expect(PageContextTabExtension.shouldDeliverCollectionResult(context(content: ""), wasForced: true, cached: nil))
        #expect(PageContextTabExtension.shouldDeliverCollectionResult(nil, wasForced: true, cached: nil))
        #expect(PageContextTabExtension.shouldDeliverCollectionResult(nil, wasForced: true, cached: context(content: "")))
    }

    @available(iOS 16, macOS 13, *)
    @Test("A forced empty result never replaces attached content", .timeLimit(.minutes(1)))
    func forcedEmptyResultKeepsAttachedContent() {
        #expect(!PageContextTabExtension.shouldDeliverCollectionResult(context(content: ""), wasForced: true, cached: context(content: "attached")))
        #expect(!PageContextTabExtension.shouldDeliverCollectionResult(nil, wasForced: true, cached: context(content: "attached")))
    }
}
