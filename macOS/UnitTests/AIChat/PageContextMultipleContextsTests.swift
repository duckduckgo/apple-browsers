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
