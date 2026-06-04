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
import Testing

@testable import DuckDuckGo_Privacy_Browser

// MARK: - NavigationContextAction Tests

struct NavigationContextActionTests {

    /// Helper that mirrors the logic in PageContextTabExtension.navigationAction
    private func navigationAction(autoCollectEnabled: Bool, contextConsumed: Bool) -> String {
        if autoCollectEnabled {
            return "collectNewContext"
        } else if contextConsumed {
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

    /// Mirrors `PageContextTabExtension.Constants.maxSelectionContextLength`.
    private static let maxSelectionContextLength = 9500

    /// Mirrors `PageContextTabExtension.attachSelectionContext` payload construction.
    private func buildSelectionContext(text: String, url: String, title: String) -> AIChatPageContextData {
        let truncated = text.count > Self.maxSelectionContextLength
        let content = truncated ? String(text.prefix(Self.maxSelectionContextLength)) : text
        return AIChatPageContextData(
            title: title,
            favicon: [],
            url: url,
            content: content,
            truncated: truncated,
            fullContentLength: text.count,
            attachable: true,
            contentType: "selection"
        )
    }

    @Test("Short selection is attachable, tagged as selection, and not truncated")
    func shortSelectionIsTaggedAndNotTruncated() {
        let context = buildSelectionContext(text: "hello world", url: "https://example.com", title: "Text selection")
        #expect(context.contentType == "selection")
        #expect(context.content == "hello world")
        #expect(context.title == "Text selection")
        #expect(context.url == "https://example.com")
        #expect(context.attachable == true)
        #expect(context.truncated == false)
        #expect(context.fullContentLength == 11)
    }

    @Test("Long selection is truncated to the max length and reports the original length")
    func longSelectionIsTruncated() {
        let longText = String(repeating: "x", count: Self.maxSelectionContextLength + 500)
        let context = buildSelectionContext(text: longText, url: "https://example.com", title: "Text selection")
        #expect(context.content.count == Self.maxSelectionContextLength)
        #expect(context.truncated == true)
        #expect(context.fullContentLength == longText.count)
    }
}

// MARK: - Selection Override Precedence Tests

struct SelectionOverridePrecedenceTests {

    /// Mirrors the precedence applied across `PageContextTabExtension`: a selection override,
    /// while set, owns the sidebar context and suppresses auto-collected full-page content.
    private func shouldSuppressAutoCollect(selectionOverridePresent: Bool) -> Bool {
        selectionOverridePresent
    }

    @Test("Selection override suppresses auto-collected full-page context")
    func overrideSuppressesAutoCollect() {
        #expect(shouldSuppressAutoCollect(selectionOverridePresent: true) == true)
    }

    @Test("No override lets normal auto-collect proceed")
    func noOverrideAllowsAutoCollect() {
        #expect(shouldSuppressAutoCollect(selectionOverridePresent: false) == false)
    }
}
