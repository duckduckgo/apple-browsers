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

// MARK: - isContextCollectionEnabled Logic Tests

/// Exercises `PageContextTabExtension`'s real decision functions (not a mirror).
struct ContextCollectionEnabledTests {

    private typealias Extension = PageContextTabExtension

    private func isContextCollectionEnabled(
        shouldForceContextCollection: Bool = false,
        isAutoPageContextSuppressed: Bool = false,
        shouldAutomaticallySendPageContext: Bool
    ) -> Bool {
        Extension.isContextCollectionEnabled(shouldForceContextCollection: shouldForceContextCollection,
                                             isAutoPageContextSuppressed: isAutoPageContextSuppressed,
                                             shouldAutomaticallySendPageContext: shouldAutomaticallySendPageContext)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Force collection overrides everything", .timeLimit(.minutes(1)))
    func forceCollectionOverrides() {
        #expect(isContextCollectionEnabled(shouldForceContextCollection: true, isAutoPageContextSuppressed: true, shouldAutomaticallySendPageContext: false) == true)
        #expect(isContextCollectionEnabled(shouldForceContextCollection: true, shouldAutomaticallySendPageContext: false) == true)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Suppression beats the auto-send setting", .timeLimit(.minutes(1)))
    func suppressionBeatsAutoSend() {
        #expect(isContextCollectionEnabled(isAutoPageContextSuppressed: true, shouldAutomaticallySendPageContext: true) == false)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Auto-send setting is respected when no overrides", .timeLimit(.minutes(1)))
    func autoSendRespected() {
        #expect(isContextCollectionEnabled(shouldAutomaticallySendPageContext: true) == true)
        #expect(isContextCollectionEnabled(shouldAutomaticallySendPageContext: false) == false)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Attaching a selection that opens the sidebar suppresses auto page-context", .timeLimit(.minutes(1)))
    func selectionAttachThatOpensSidebarSuppressesPageContext() {
        let suppressed = Extension.shouldSuppressAutoPageContextOnSelectionAttach(isSidebarVisible: false)
        #expect(suppressed == true)
        // The whole point of the fix: auto-attach ON must not also attach the page.
        #expect(isContextCollectionEnabled(isAutoPageContextSuppressed: suppressed, shouldAutomaticallySendPageContext: true) == false)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Attaching a selection with the sidebar already open leaves page context alone", .timeLimit(.minutes(1)))
    func selectionAttachWithOpenSidebarKeepsPageContext() {
        let suppressed = Extension.shouldSuppressAutoPageContextOnSelectionAttach(isSidebarVisible: true)
        #expect(suppressed == false)
        #expect(isContextCollectionEnabled(isAutoPageContextSuppressed: suppressed, shouldAutomaticallySendPageContext: true) == true)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Ask About Page still forces collection after a selection attach", .timeLimit(.minutes(1)))
    func askAboutPageOverridesSelectionSuppression() {
        let suppressed = Extension.shouldSuppressAutoPageContextOnSelectionAttach(isSidebarVisible: false)
        #expect(isContextCollectionEnabled(shouldForceContextCollection: true, isAutoPageContextSuppressed: suppressed, shouldAutomaticallySendPageContext: false) == true)
    }
}

// MARK: - Auto-attach suppression Tests

/// The sidebar's page-context rules under `aiChatPageContextAutoAttach`, plus the per-page behavior
/// kept when the flag is off.
struct AutoPageContextSuppressionTests {

    @available(iOS 16, macOS 13, *)
    @Test("Nothing is suppressed at first, so opening the sidebar attaches the page", .timeLimit(.minutes(1)))
    func startsUnsuppressed() {
        var suppression = AutoPageContextSuppression()
        suppression.sidebarOpened()
        #expect(suppression.suppressesAutoAttach == false)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A remove stays in effect as the user keeps navigating", .timeLimit(.minutes(1)))
    func removeLastsAcrossNavigation() {
        var suppression = AutoPageContextSuppression()
        suppression.userRemovedContext(keepAcrossNavigation: true)
        suppression.navigatedToNewURL()
        suppression.navigatedToNewURL()
        #expect(suppression.suppressesAutoAttach == true)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Attaching again resumes automatic updates on later navigations", .timeLimit(.minutes(1)))
    func attachResumesAutoUpdates() {
        var suppression = AutoPageContextSuppression()
        suppression.userRemovedContext(keepAcrossNavigation: true)
        suppression.userAttachedContext()
        #expect(suppression.suppressesAutoAttach == false)
        suppression.navigatedToNewURL()
        #expect(suppression.suppressesAutoAttach == false)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Reopening the sidebar after a remove attaches the page again", .timeLimit(.minutes(1)))
    func reopeningSidebarClearsRemove() {
        var suppression = AutoPageContextSuppression()
        suppression.userRemovedContext(keepAcrossNavigation: true)
        suppression.sidebarOpened()
        #expect(suppression.suppressesAutoAttach == false)
    }

    @available(iOS 16, macOS 13, *)
    @Test("With the flag off a remove lasts only until the next navigation", .timeLimit(.minutes(1)))
    func removeWithoutFlagIsPerPage() {
        var suppression = AutoPageContextSuppression()
        suppression.userRemovedContext(keepAcrossNavigation: false)
        #expect(suppression.suppressesAutoAttach == true)
        suppression.navigatedToNewURL()
        #expect(suppression.suppressesAutoAttach == false)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A selection action that opens the sidebar holds back only the current page", .timeLimit(.minutes(1)))
    func selectionActionIsPerPage() {
        var suppression = AutoPageContextSuppression()
        suppression.selectionActionOpenedSidebar()
        suppression.sidebarOpened()
        #expect(suppression.suppressesAutoAttach == true)
        suppression.navigatedToNewURL()
        #expect(suppression.suppressesAutoAttach == false)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Attaching by hand also lifts a selection action's suppression", .timeLimit(.minutes(1)))
    func attachClearsSelectionSuppression() {
        var suppression = AutoPageContextSuppression()
        suppression.selectionActionOpenedSidebar()
        suppression.userAttachedContext()
        #expect(suppression.suppressesAutoAttach == false)
    }
}

// MARK: - Collect only while the chat is open Tests

struct CollectWhileChatOpenTests {

    private typealias Extension = PageContextTabExtension

    @available(iOS 16, macOS 13, *)
    @Test("Automatic collects skip tabs without an open chat", .timeLimit(.minutes(1)))
    func automaticCollectSkipsClosedChat() {
        for trigger in [PageContextExtractionTrigger.navigation, .auto, .tabContent] {
            #expect(Extension.shouldCollect(trigger: trigger, isChatOpen: false, collectsOnlyWhileChatOpen: true) == false)
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("A user request collects even before the chat is open", .timeLimit(.minutes(1)))
    func userRequestAlwaysCollects() {
        #expect(Extension.shouldCollect(trigger: .userRequest, isChatOpen: false, collectsOnlyWhileChatOpen: true) == true)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Automatic collects run while the chat is open", .timeLimit(.minutes(1)))
    func automaticCollectRunsWithOpenChat() {
        #expect(Extension.shouldCollect(trigger: .navigation, isChatOpen: true, collectsOnlyWhileChatOpen: true) == true)
    }

    @available(iOS 16, macOS 13, *)
    @Test("With the flag off a closed chat still collects, as before", .timeLimit(.minutes(1)))
    func flagOffCollectsWithClosedChat() {
        #expect(Extension.shouldCollect(trigger: .navigation, isChatOpen: false, collectsOnlyWhileChatOpen: false) == true)
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

// MARK: - Collection result delivery

/// `PageContextTabExtension.shouldDeliverCollectionResult`: which collection results reach
/// `handle()`. A forced (user-requested) collect must resolve even when empty — the FE awaits
/// the `getAIChatPageContext` response — but must never replace attached content.
struct PageContextCollectionResultDeliveryTests {

    private func context(content: String) -> AIChatPageContextData {
        AIChatPageContextData(title: "Title", favicon: [], url: "https://example.com", content: content, truncated: false, fullContentLength: content.count)
    }

    private var document: AIChatPageContextData {
        AIChatPageContextData.document(title: "Spec", url: "https://example.com/spec.pdf", mimeType: AIChatPageContextData.pdfMIMEType, data: "JVBERi0=")
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

    @available(iOS 16, macOS 13, *)
    @Test("An automatic document collect is skipped while the webview still displays the previous document", .timeLimit(.minutes(1)))
    func documentCollectSkippedOnDocumentMismatch() {
        let old = URL(string: "https://old.com/a.pdf")!
        let new = URL(string: "https://new.com/b.pdf")!
        #expect(PageContextTabExtension.shouldRunDocumentCollect(trigger: .navigation, webViewURL: old, contentURL: new) == false)
        #expect(PageContextTabExtension.shouldRunDocumentCollect(trigger: .tabContent, webViewURL: old, contentURL: new) == false)
        #expect(PageContextTabExtension.shouldRunDocumentCollect(trigger: .navigation, webViewURL: new, contentURL: new) == true)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A user-initiated document collect proceeds regardless of document mismatch", .timeLimit(.minutes(1)))
    func userDocumentCollectAlwaysProceeds() {
        let old = URL(string: "https://old.com/a.pdf")!
        let new = URL(string: "https://new.com/b.pdf")!
        #expect(PageContextTabExtension.shouldRunDocumentCollect(trigger: .userRequest, webViewURL: old, contentURL: new) == true)
        #expect(PageContextTabExtension.shouldRunDocumentCollect(trigger: .auto, webViewURL: old, contentURL: new) == true)
        #expect(PageContextTabExtension.shouldRunDocumentCollect(trigger: .navigation, webViewURL: nil, contentURL: new) == true)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Turning auto-attach on collects afresh when the cache holds only metadata", .timeLimit(.minutes(1)))
    func metadataOnlyCacheIsNotReused() {
        let metadataOnly = AIChatPageContextData.document(title: "Spec", url: "https://example.com/spec.pdf", mimeType: AIChatPageContextData.pdfMIMEType, data: nil, attachable: true, attached: false)
        #expect(PageContextTabExtension.shouldReuseCachedContext(metadataOnly) == false)
        #expect(PageContextTabExtension.shouldReuseCachedContext(document) == true)
        #expect(PageContextTabExtension.shouldReuseCachedContext(context(content: "body")) == true)
        #expect(PageContextTabExtension.shouldReuseCachedContext(context(content: "")) == false)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A document result counts as an attached page even though its content is empty", .timeLimit(.minutes(1)))
    func documentResultIsDelivered() {
        #expect(PageContextTabExtension.shouldDeliverCollectionResult(document, wasForced: false, cached: nil))
        #expect(!PageContextTabExtension.shouldDeliverCollectionResult(context(content: ""), wasForced: true, cached: document),
                "An empty markdown result must not replace an attached document")
    }

    @available(iOS 16, macOS 13, *)
    @Test("A document read that fails resolves the awaiting request, but never wipes an attached page", .timeLimit(.minutes(1)))
    func failedDocumentReadRespectsAttachedContent() {
        // The `.unavailable` branch asks this with a nil result: nothing came back to deliver.
        #expect(PageContextTabExtension.shouldDeliverCollectionResult(nil, wasForced: true, cached: nil))
        #expect(!PageContextTabExtension.shouldDeliverCollectionResult(nil, wasForced: true, cached: document))
        #expect(!PageContextTabExtension.shouldDeliverCollectionResult(nil, wasForced: false, cached: nil),
                "An unforced failure has nobody waiting on it")
    }
}
