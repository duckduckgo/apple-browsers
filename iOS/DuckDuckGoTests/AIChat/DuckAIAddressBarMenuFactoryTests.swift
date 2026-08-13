//
//  DuckAIAddressBarMenuFactoryTests.swift
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

import DesignResourcesKitIcons
import UIKit
import XCTest
@testable import DuckDuckGo

final class DuckAIAddressBarMenuFactoryTests: XCTestCase {

    private func makeActions(pageFavicon: UIImage? = nil,
                             onNewChat: @escaping () -> Void = {},
                             onAskAboutPage: @escaping () -> Void = {}) -> [UIMenuElement] {
        DuckAIAddressBarMenuFactory.makeActions(
            pageFavicon: pageFavicon,
            onNewChat: onNewChat,
            onAskAboutPage: onAskAboutPage
        )
    }

    /// Each action is wrapped in its own inline group so UIKit draws a separator between them.
    private func flattenedActions(_ elements: [UIMenuElement]) -> [UIAction] {
        elements.flatMap { element -> [UIAction] in
            if let action = element as? UIAction { return [action] }
            guard let menu = element as? UIMenu else { return [] }
            return menu.children.compactMap { $0 as? UIAction }
        }
    }

    // MARK: - Structure

    func testMenuIsTitledDuckAi() {
        let menu = DuckAIAddressBarMenuFactory.makeMenu(pageFavicon: nil, onNewChat: {}, onAskAboutPage: {})
        XCTAssertEqual(menu.title, UserText.duckAiFeatureName)
    }

    func testActionsAreSplitIntoSeparateInlineGroupsSoASeparatorIsDrawn() {
        let elements = makeActions()
        let groups = elements.compactMap { $0 as? UIMenu }

        XCTAssertEqual(groups.count, 2)
        XCTAssertTrue(groups.allSatisfy { $0.options.contains(.displayInline) })
        XCTAssertTrue(groups.allSatisfy { $0.children.count == 1 })
    }

    func testNewChatIsFirstAndAskAboutPageIsSecond() {
        let titles = flattenedActions(makeActions()).map(\.title)
        XCTAssertEqual(titles, [UserText.duckAiAddressBarMenuNewChat, UserText.aiChatAttachmentOptionAskAboutPage])
    }

    // MARK: - Icons

    func testAskAboutPageUsesThePageFaviconWhenAvailable() {
        let favicon = UIImage(systemName: "globe")!
        let askAboutPage = flattenedActions(makeActions(pageFavicon: favicon))[1]
        XCTAssertIdentical(askAboutPage.image, favicon)
    }

    func testAskAboutPageFallsBackToAGlyphWithoutAFavicon() {
        let askAboutPage = flattenedActions(makeActions())[1]
        XCTAssertEqual(askAboutPage.image, DesignSystemImages.Glyphs.Size16.tabContent)
    }

    func testNewChatAlwaysUsesTheComposeGlyph() {
        let favicon = UIImage(systemName: "globe")!
        let newChat = flattenedActions(makeActions(pageFavicon: favicon))[0]
        XCTAssertEqual(newChat.image, DesignSystemImages.Glyphs.Size16.compose)
    }

    // MARK: - Handlers

    func testSelectingAnActionInvokesItsOwnHandler() throws {
        guard #available(iOS 16.0, *) else {
            throw XCTSkip("UIAction.performWithSender requires iOS 16")
        }

        var newChatCount = 0
        var askAboutPageCount = 0
        let actions = flattenedActions(makeActions(onNewChat: { newChatCount += 1 },
                                                  onAskAboutPage: { askAboutPageCount += 1 }))

        actions[0].performWithSender(nil, target: nil)
        XCTAssertEqual(newChatCount, 1)
        XCTAssertEqual(askAboutPageCount, 0)

        actions[1].performWithSender(nil, target: nil)
        XCTAssertEqual(newChatCount, 1)
        XCTAssertEqual(askAboutPageCount, 1)
    }
}
