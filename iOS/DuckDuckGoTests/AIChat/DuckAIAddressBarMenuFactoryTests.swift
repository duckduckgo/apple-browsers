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
import FeatureFlags_iOS
import UIKit
import XCTest
@testable import DuckDuckGo

final class DuckAIAddressBarMenuFactoryTests: XCTestCase {

    private func makeActions(featureFlagger: MockFeatureFlagger = MockFeatureFlagger(
                                enabledFeatureFlags: [.aiChatNativeChatHistory, .aiChatAddressBarRecentChats]),
                             userInterfaceIdiom: UIUserInterfaceIdiom = .phone,
                             isHomeTab: Bool = false,
                             onNewChat: @escaping () -> Void = {},
                             onAskAboutPage: @escaping () -> Void = {},
                             onRecentChats: @escaping () -> Void = {}) -> [UIMenuElement] {
        DuckAIAddressBarMenuFactory.makeActions(
            featureFlagger: featureFlagger,
            userInterfaceIdiom: userInterfaceIdiom,
            isHomeTab: isHomeTab,
            onNewChat: onNewChat,
            onAskAboutPage: onAskAboutPage,
            onRecentChats: onRecentChats
        )
    }

    private func flattenedActions(_ elements: [UIMenuElement]) -> [UIAction] {
        elements.flatMap { element -> [UIAction] in
            if let action = element as? UIAction { return [action] }
            guard let menu = element as? UIMenu else { return [] }
            return menu.children.compactMap { $0 as? UIAction }
        }
    }

    // MARK: - Structure

    func testNewChatAndAskAboutPageAreGroupedAboveRecentChats() throws {
        let groups = makeActions().compactMap { $0 as? UIMenu }

        XCTAssertEqual(groups.count, 2)
        XCTAssertTrue(groups.allSatisfy { $0.options.contains(.displayInline) })
        let newChatGroup = try XCTUnwrap(groups.first)
        let historyGroup = try XCTUnwrap(groups.last)
        XCTAssertEqual(newChatGroup.children.compactMap { ($0 as? UIAction)?.title },
                       [UserText.duckAiAddressBarMenuNewChat, UserText.aiChatAttachmentOptionAskAboutPage])
        XCTAssertEqual(historyGroup.children.compactMap { ($0 as? UIAction)?.title },
                       [UserText.actionChats])
    }

    func testHomeTabOffersNewChatAndChatsWithoutAskAboutPage() throws {
        let groups = makeActions(isHomeTab: true).compactMap { $0 as? UIMenu }
        XCTAssertEqual(groups.count, 2)
        XCTAssertTrue(groups.allSatisfy { $0.options.contains(.displayInline) })
        XCTAssertEqual(try XCTUnwrap(groups.first).children.compactMap { ($0 as? UIAction)?.title },
                       [UserText.duckAiAddressBarMenuNewChat])
        XCTAssertEqual(try XCTUnwrap(groups.last).children.compactMap { ($0 as? UIAction)?.title },
                       [UserText.actionChats])
    }

    func testHomeTabActionsInvokeOnlyNewChatAndHistoryHandlers() throws {
        guard #available(iOS 16.0, *) else {
            throw XCTSkip("UIAction.performWithSender requires iOS 16")
        }
        var selected: [String] = []
        let actions = flattenedActions(makeActions(isHomeTab: true,
                                                  onNewChat: { selected.append("new") },
                                                  onAskAboutPage: { selected.append("page") },
                                                  onRecentChats: { selected.append("history") }))
        for action in actions {
            action.performWithSender(nil, target: nil)
        }
        XCTAssertEqual(selected, ["new", "history"])
    }

    func testRecentChatsFollowsNewChatAndAskAboutPage() {
        let titles = flattenedActions(makeActions()).map(\.title)
        XCTAssertEqual(titles, [UserText.duckAiAddressBarMenuNewChat,
                               UserText.aiChatAttachmentOptionAskAboutPage,
                               UserText.actionChats])
    }

    func testRecentChatsGroupIsOmittedWhenFlagIsDisabled() {
        let elements = makeActions(featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.aiChatNativeChatHistory]))
        let groups = elements.compactMap { $0 as? UIMenu }
        XCTAssertEqual(groups.count, 1)
        XCTAssertTrue(groups.allSatisfy { $0.options.contains(.displayInline) && $0.children.count == 2 })
        let titles = flattenedActions(elements).map(\.title)
        XCTAssertEqual(titles, [UserText.duckAiAddressBarMenuNewChat, UserText.aiChatAttachmentOptionAskAboutPage])
    }

    /// iPad opens the duck.ai chats sidebar instead of the native history, so it only needs the kill switch.
    func testRecentChatsRequiresBothFlagsOnIPhoneAndOnlyTheKillSwitchOnIPad() {
        let cases: [(flags: [FeatureFlag], idiom: UIUserInterfaceIdiom, showsRecentChats: Bool)] = [
            ([], .phone, false),
            ([.aiChatNativeChatHistory], .phone, false),
            ([.aiChatAddressBarRecentChats], .phone, false),
            ([.aiChatNativeChatHistory, .aiChatAddressBarRecentChats], .phone, true),
            ([], .pad, false),
            ([.aiChatNativeChatHistory], .pad, false),
            ([.aiChatAddressBarRecentChats], .pad, true),
            ([.aiChatNativeChatHistory, .aiChatAddressBarRecentChats], .pad, true)
        ]

        for testCase in cases {
            XCTAssertEqual(DuckAIAddressBarMenuFactory.isChatHistoryAvailable(
                featureFlagger: MockFeatureFlagger(enabledFeatureFlags: testCase.flags),
                userInterfaceIdiom: testCase.idiom), testCase.showsRecentChats && testCase.idiom == .phone)
            let actions = flattenedActions(makeActions(
                featureFlagger: MockFeatureFlagger(enabledFeatureFlags: testCase.flags),
                userInterfaceIdiom: testCase.idiom))
            let expectedTitles = [UserText.duckAiAddressBarMenuNewChat, UserText.aiChatAttachmentOptionAskAboutPage]
                + (testCase.showsRecentChats ? [UserText.actionChats] : [])
            XCTAssertEqual(actions.map(\.title), expectedTitles, "Flags: \(testCase.flags), device: \(testCase.idiom)")
        }
    }

    func testFactoryUsesCurrentFlagValuesOnEachCall() {
        let featureFlagger = MockFeatureFlagger()
        XCTAssertEqual(flattenedActions(makeActions(featureFlagger: featureFlagger)).count, 2)

        featureFlagger.enabledFeatureFlags = [.aiChatNativeChatHistory, .aiChatAddressBarRecentChats]
        XCTAssertEqual(flattenedActions(makeActions(featureFlagger: featureFlagger)).count, 3)

        featureFlagger.enabledFeatureFlags = [.aiChatNativeChatHistory]
        XCTAssertEqual(flattenedActions(makeActions(featureFlagger: featureFlagger)).count, 2)

        featureFlagger.enabledFeatureFlags = [.aiChatNativeChatHistory, .aiChatAddressBarRecentChats]
        XCTAssertEqual(flattenedActions(makeActions(featureFlagger: featureFlagger)).count, 3)

        featureFlagger.enabledFeatureFlags = [.aiChatAddressBarRecentChats]
        XCTAssertEqual(flattenedActions(makeActions(featureFlagger: featureFlagger)).count, 2)
    }

    // MARK: - Icons

    /// A fixed glyph rather than the page favicon, so the row reads the same on every site.
    func testAskAboutPageUsesTheChevronCircleDownGlyph() {
        let askAboutPage = flattenedActions(makeActions())[1]
        XCTAssertEqual(askAboutPage.image, DesignSystemImages.Glyphs.Size16.chevronCircleDown)
    }

    func testRecentChatsUsesTheSupplied16PointTemplateGlyph() throws {
        let recentChats = flattenedActions(makeActions())[2]
        let icon = try XCTUnwrap(recentChats.image)
        XCTAssertEqual(icon, DesignSystemImages.Glyphs.Size16.chats)
        XCTAssertEqual(icon.size, CGSize(width: 16, height: 16))
        XCTAssertEqual(icon.renderingMode, .alwaysTemplate)
    }

    func testNewChatUsesTheComposeGlyph() {
        let newChat = flattenedActions(makeActions())[0]
        XCTAssertEqual(newChat.image, DesignSystemImages.Glyphs.Size16.compose)
    }

    // MARK: - Handlers

    func testSelectingAnActionInvokesItsOwnHandler() throws {
        guard #available(iOS 16.0, *) else {
            throw XCTSkip("UIAction.performWithSender requires iOS 16")
        }

        var newChatCount = 0
        var askAboutPageCount = 0
        var recentChatsCount = 0
        let actions = flattenedActions(makeActions(onNewChat: { newChatCount += 1 },
                                                  onAskAboutPage: { askAboutPageCount += 1 },
                                                  onRecentChats: { recentChatsCount += 1 }))

        actions[0].performWithSender(nil, target: nil)
        XCTAssertEqual(newChatCount, 1)
        XCTAssertEqual(askAboutPageCount, 0)
        XCTAssertEqual(recentChatsCount, 0)

        actions[1].performWithSender(nil, target: nil)
        XCTAssertEqual(newChatCount, 1)
        XCTAssertEqual(askAboutPageCount, 1)
        XCTAssertEqual(recentChatsCount, 0)

        actions[2].performWithSender(nil, target: nil)
        XCTAssertEqual(newChatCount, 1)
        XCTAssertEqual(askAboutPageCount, 1)
        XCTAssertEqual(recentChatsCount, 1)
    }
}
