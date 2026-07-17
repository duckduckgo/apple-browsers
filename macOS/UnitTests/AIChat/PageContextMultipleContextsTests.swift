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

    @Test("Auto-collect ON returns collectNewContext regardless of consumed state")
    func autoCollectOnCollectsNewContext() {
        #expect(navigationAction(autoCollectEnabled: true, contextConsumed: false) == "collectNewContext")
        #expect(navigationAction(autoCollectEnabled: true, contextConsumed: true) == "collectNewContext")
    }

    @Test("Auto-collect OFF with consumed context returns sendNavigationSignal")
    func autoCollectOffConsumedSendsSignal() {
        #expect(navigationAction(autoCollectEnabled: false, contextConsumed: true) == "sendNavigationSignal")
    }

    @Test("Auto-collect OFF without consumed context returns keepExistingContext")
    func autoCollectOffNotConsumedKeeps() {
        #expect(navigationAction(autoCollectEnabled: false, contextConsumed: false) == "keepExistingContext")
    }

    // fromAttachablePage = false (navigating FROM NTP/settings/etc. to a URL)

    @Test("NTP to URL with auto-collect OFF and no prior chat sends navigation signal")
    func ntpToURLAutoCollectOffNoChat() {
        #expect(navigationAction(autoCollectEnabled: false, contextConsumed: false, fromAttachablePage: false) == "sendNavigationSignal")
    }

    @Test("NTP to URL with auto-collect ON collects new context")
    func ntpToURLAutoCollectOn() {
        #expect(navigationAction(autoCollectEnabled: true, contextConsumed: false, fromAttachablePage: false) == "collectNewContext")
    }

    @Test("NTP to URL with consumed context sends navigation signal")
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

    @Test("Force collection overrides everything")
    func forceCollectionOverrides() {
        #expect(isContextCollectionEnabled(shouldForceContextCollection: true, userRemovedContext: true, shouldAutomaticallySendPageContext: false) == true)
        #expect(isContextCollectionEnabled(shouldForceContextCollection: true, userRemovedContext: false, shouldAutomaticallySendPageContext: false) == true)
    }

    @Test("User removed context suppresses auto-collection")
    func userRemovedSuppresses() {
        #expect(isContextCollectionEnabled(shouldForceContextCollection: false, userRemovedContext: true, shouldAutomaticallySendPageContext: true) == false)
    }

    @Test("Auto-send setting is respected when no overrides")
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

    @Test("Attachable context resets consumed flag")
    func attachableContextResets() {
        let context = AIChatPageContextData(title: "Test", favicon: [], url: "https://example.com", content: "content", truncated: false, fullContentLength: 100)
        #expect(shouldResetConsumedFlag(pageContext: context) == true)
    }

    @Test("Non-attachable context does not reset consumed flag")
    func nonAttachableDoesNotReset() {
        let context = AIChatPageContextData(title: "NTP", favicon: [], url: "", content: "", truncated: false, fullContentLength: 0, attachable: false)
        #expect(shouldResetConsumedFlag(pageContext: context) == false)
    }

    @Test("Nil context does not reset consumed flag")
    func nilDoesNotReset() {
        #expect(shouldResetConsumedFlag(pageContext: nil) == false)
    }

    @Test("Context with attachable=true resets consumed flag")
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

    @Test("Short selection carries the generic title and is not truncated")
    func shortSelectionIsTaggedAndNotTruncated() {
        let item = buildSelectionItem(text: "hello world", url: "https://example.com")
        #expect(item.content == "hello world")
        #expect(item.title == "Text selection")
        #expect(item.url == "https://example.com")
        #expect(item.truncated == false)
        #expect(item.fullContentLength == 11)
        #expect(item.wordCount == 2)
    }

    @Test("Word count covers the full selection even when truncated")
    func wordCountReflectsFullSelection() {
        // 6000 two-char words separated by spaces → 11999 chars, truncated at 9500, but wordCount is the full 6000.
        let longText = Array(repeating: "ab", count: 6000).joined(separator: " ")
        let item = buildSelectionItem(text: longText, url: "https://example.com")
        #expect(item.truncated == true)
        #expect(item.wordCount == 6000)
    }

    @Test("Long selection is truncated to the max length and reports the original length")
    func longSelectionIsTruncated() {
        let longText = String(repeating: "x", count: Self.maxSelectionContextLength + 500)
        let item = buildSelectionItem(text: longText, url: "https://example.com")
        #expect(item.content.count == Self.maxSelectionContextLength)
        #expect(item.truncated == true)
        #expect(item.fullContentLength == longText.count)
    }

    @Test("Each attached selection gets a unique id")
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

    @Test("First automatic collect reports; the navigation's later automatic collects are suppressed")
    func firstAutomaticReportsRestSuppressed() {
        let dedup = Dedup()
        #expect(dedup.shouldReport(.navigation) == true)   // didCommit re-collect
        #expect(dedup.shouldReport(.navigation) == false)  // didFinish re-collect
        #expect(dedup.shouldReport(.tabContent) == false)  // signals-only harvest
    }

    @Test("navigation and tabContent share the single per-navigation slot")
    func navigationAndTabContentShareSlot() {
        let dedup = Dedup()
        #expect(dedup.shouldReport(.tabContent) == true)
        #expect(dedup.shouldReport(.navigation) == false)
    }

    @Test("Navigation to a new URL re-arms automatic reporting")
    func navigationResetReArms() {
        let dedup = Dedup()
        #expect(dedup.shouldReport(.navigation) == true)
        #expect(dedup.shouldReport(.navigation) == false)
        dedup.resetForNavigation()
        #expect(dedup.shouldReport(.navigation) == true)
    }

    @Test("User- and setting-initiated collects always report and never consume the slot")
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

    @Test("Native special page (non-URL content) reports prevented(internalPage)")
    func nativePageReportsInternalPagePrevented() {
        #expect(sidebarOpenOutcome(isURL: false, preventedReason: nil, isContextCollectionEnabled: true) == .prevented("internalPage"))
    }

    @Test("Non-attachable URL reports prevented with the blocklist category, no interaction needed")
    func nonAttachableURLReportsPrevented() {
        #expect(sidebarOpenOutcome(isURL: true, preventedReason: "pdf", isContextCollectionEnabled: false) == .prevented("pdf"))
        #expect(sidebarOpenOutcome(isURL: true, preventedReason: "image", isContextCollectionEnabled: true) == .prevented("image"))
    }

    @Test("Attachable URL with auto-collect ON re-collects so success/failure fire live")
    func attachableAutoOnReCollects() {
        #expect(sidebarOpenOutcome(isURL: true, preventedReason: nil, isContextCollectionEnabled: true) == .collect)
    }

    @Test("Attachable URL with auto-collect OFF reports nothing on open (awaits user tap / signals-only)")
    func attachableAutoOffReportsNone() {
        #expect(sidebarOpenOutcome(isURL: true, preventedReason: nil, isContextCollectionEnabled: false) == .none)
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

    @Test("First sidebar open measures; re-opening on the same page (kept session) does not")
    func firstOpenMeasuresReopenDoesNot() {
        let guardState = Guard()
        #expect(guardState.shouldMeasureOnSidebarOpen(isVisible: true, measurementEnabled: true) == true)
        #expect(guardState.shouldMeasureOnSidebarOpen(isVisible: true, measurementEnabled: true) == false)
    }

    @Test("A collection that already reported this navigation suppresses the sidebar-open measurement")
    func collectionReportSuppressesMeasurement() {
        let guardState = Guard()
        guardState.markCollectionReported()
        #expect(guardState.shouldMeasureOnSidebarOpen(isVisible: true, measurementEnabled: true) == false)
    }

    @Test("Navigation to a new URL re-arms the sidebar-open measurement")
    func navigationReArmsMeasurement() {
        let guardState = Guard()
        #expect(guardState.shouldMeasureOnSidebarOpen(isVisible: true, measurementEnabled: true) == true)
        guardState.resetForNavigation()
        #expect(guardState.shouldMeasureOnSidebarOpen(isVisible: true, measurementEnabled: true) == true)
    }

    @Test("A hidden sidebar or absent blocklist config never measures and never consumes the slot")
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

    @Test("Full collection (auto-attach on / user-forced) reports its extraction outcome")
    func fullCollectionReports() {
        #expect(firesExtractionOutcome(isContextCollectionEnabled: true, pendingSignalsOnly: false) == true)
    }

    @Test("Signals-only harvest does not report success/failed")
    func signalsOnlyDoesNotReport() {
        #expect(firesExtractionOutcome(isContextCollectionEnabled: false, pendingSignalsOnly: true) == false)
    }

    @Test("Unsolicited collection result reports nothing")
    func unsolicitedReportsNothing() {
        #expect(firesExtractionOutcome(isContextCollectionEnabled: false, pendingSignalsOnly: false) == false)
    }
}
