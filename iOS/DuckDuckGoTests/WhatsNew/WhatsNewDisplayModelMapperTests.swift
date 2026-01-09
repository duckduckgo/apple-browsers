//
//  WhatsNewDisplayModelMapperTests.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import Testing
import RemoteMessaging
import RemoteMessagingTestsUtils
@testable import DuckDuckGo

@Suite("What's New - Display Model Mapper")
final class WhatsNewDisplayModelMapperTests {
    private let sut = WhatsNewDisplayModelMapper()

    @Test("Check Mapper Creates Display Model From Cards List Message")
    func whenCardsListMessageThenDisplayModelIsCreated() throws {
        // GIVEN
        let items = [
            RemoteMessageModelType.ListItem.makeTwoLinesListItem(id: "item-1", titleText: "Feature 1"),
            RemoteMessageModelType.ListItem.makeTwoLinesListItem(id: "item-2", titleText: "Feature 2"),
            RemoteMessageModelType.ListItem.makeTwoLinesListItem(id: "item-3", titleText: "Feature 3")
        ]
        let message = RemoteMessageModel.makeCardsListMessage(
            titleText: "What's New in DuckDuckGo",
            items: items,
            primaryActionText: "Get Started",
            primaryAction: .dismiss
        )

        // WHEN
        let displayModel = try #require(
            sut.makeDisplayModel(
                from: message,
                onMessageAppear: { },
                onItemAppear: { _ in },
                onItemAction: { _, _ in },
                onPrimaryAction: { _ in },
                onDismiss: { }
            )
        )

        // THEN
        #expect(displayModel.screenTitle == "What's New in DuckDuckGo")
        #expect(displayModel.items.count == 3)
        #expect(displayModel.primaryAction?.title == "Get Started")
    }

    @Test("Check Mapper Returns Nil For Non-CardsList Message")
    func whenNonCardsListMessageThenReturnsNil() {
        // GIVEN
        let message = RemoteMessageModel(
            id: "test-message-id",
            surfaces: .modal,
            content: .small(titleText: "Title", descriptionText: "Description"),
            matchingRules: [],
            exclusionRules: [],
            isMetricsEnabled: true
        )

        // WHEN
        let displayModel = sut.makeDisplayModel(
            from: message,
            onMessageAppear: { },
            onItemAppear: { _ in },
            onItemAction: { _, _ in },
            onPrimaryAction: { _ in },
            onDismiss: { }
        )

        // THEN
        #expect(displayModel == nil)
    }

    // MARK: - Item Mapping Tests

    @Test("Check Mapper Correctly Maps Item Properties")
    func whenItemsHavePropertiesThenTheyAreMappedCorrectly() throws {
        // GIVEN
        let items = [
            RemoteMessageModelType.ListItem.makeTwoLinesListItem(
                id: "item-1",
                titleText: "Privacy Features",
                descriptionText: "Block trackers automatically",
                placeholder: .ddgAnnounce
            )
        ]
        let message = RemoteMessageModel.makeCardsListMessage(items: items)

        // WHEN
        let displayModel = try #require(
            sut.makeDisplayModel(
                from: message,
                onMessageAppear: { },
                onItemAppear: { _ in },
                onItemAction: { _, _ in },
                onPrimaryAction: { _ in },
                onDismiss: { }
            )
        )

        // THEN
        #expect(displayModel.items.count == 1)
        let card = try #require(displayModel.items.first?.twoLinesCard)
        #expect(card.icon == "RemoteMessageDDGAnnouncement")
        #expect(card.title == "Privacy Features")
        #expect(card.description == "Block trackers automatically")
    }

    @Test("Check Mapper Creates Items With And Without Actions")
    func whenSomeItemsHaveActionsThenOnlyThoseHaveOnTapAction() throws {
        // GIVEN
        let items = [
            RemoteMessageModelType.ListItem.makeTwoLinesListItem(id: "item-1", action: .urlInContext(value: "https://example.com")),
            RemoteMessageModelType.ListItem.makeTwoLinesListItem(id: "item-2", action: nil),
            RemoteMessageModelType.ListItem.makeTwoLinesListItem(id: "item-3", action: .navigation(value: .importPasswords))
        ]
        let message = RemoteMessageModel.makeCardsListMessage(items: items)

        // WHEN
        let displayModel = try #require(
            sut.makeDisplayModel(
                from: message,
                onMessageAppear: { },
                onItemAppear: { _ in },
                onItemAction: { _, _ in },
                onPrimaryAction: { _ in },
                onDismiss: { }
            )
        )

        // THEN
        #expect(displayModel.items.count == 3)
        #expect(displayModel.items[safe: 0]?.twoLinesCard?.onTapAction != nil)
        #expect(displayModel.items[safe: 1]?.twoLinesCard?.onTapAction == nil)
        #expect(displayModel.items[safe: 2]?.twoLinesCard?.onTapAction != nil)
    }

    @Test(
        "Check Mapper Sets Disclosure Icon Based On Action Presence",
        arguments: [
            (RemoteAction.urlInContext(value: "https://example.com"), true),
            (RemoteAction.navigation(value: .importPasswords), true),
            (RemoteAction.navigation(value: .settings), true),
            (RemoteAction.url(value: "https://example.com"), true),
            (nil, false)
        ] as [(RemoteAction?, Bool)]
    )
    func whenItemHasActionThenDisclosureIconIsSetAccordingly(action: RemoteAction?, shouldHaveIcon: Bool) throws {
        // GIVEN
        let item = RemoteMessageModelType.ListItem.makeTwoLinesListItem(id: "test-item", action: action)
        let message = RemoteMessageModel.makeCardsListMessage(items: [item])

        // WHEN
        let displayModel = try #require(
            sut.makeDisplayModel(
                from: message,
                onMessageAppear: { },
                onItemAppear: { _ in },
                onItemAction: { _, _ in },
                onPrimaryAction: { _ in },
                onDismiss: { }
            )
        )

        // THEN
        if shouldHaveIcon {
            #expect(displayModel.items.first?.twoLinesCard?.disclosureIcon != nil)
        } else {
            #expect(displayModel.items.first?.twoLinesCard?.disclosureIcon == nil)
        }
    }

    @Test("Check Message Appear Callback Is Set In Display Model")
    func whenDisplayModelCreatedThenMessageAppearCallbackIsSet() throws {
        // GIVEN
        let message = RemoteMessageModel.makeCardsListMessage()
        var messageAppearCalled = false

        // WHEN
        let displayModel = try #require(
            sut.makeDisplayModel(
                from: message,
                onMessageAppear: {
                    messageAppearCalled = true
                },
                onItemAppear: { _ in },
                onItemAction: { _, _ in },
                onPrimaryAction: { _ in },
                onDismiss: { }
            )
        )

        // THEN
        #expect(displayModel.onAppear != nil)

        // WHEN - Invoke the onAppear callback
        displayModel.onAppear?()

        // THEN
        #expect(messageAppearCalled)
    }

    @Test("Check Section Items Are Mapped Correctly")
    func whenListHasSectionThenSectionIsMapped() throws {
        // GIVEN
        let items = [
            RemoteMessageModelType.ListItem.makeTitledSectionListItem(id: "section-1", titleText: "Section Title", itemIDs: ["item-1", "item-2"]),
            RemoteMessageModelType.ListItem.makeTwoLinesListItem(id: "item-1"),
            RemoteMessageModelType.ListItem.makeTwoLinesListItem(id: "item-2")
        ]
        let message = RemoteMessageModel.makeCardsListMessage(items: items)

        // WHEN
        let displayModel = try #require(
            sut.makeDisplayModel(
                from: message,
                onMessageAppear: { },
                onItemAppear: { _ in },
                onItemAction: { _, _ in },
                onPrimaryAction: { _ in },
                onDismiss: { }
            )
        )

        // THEN
        #expect(displayModel.items.count == 3)
        let section = try #require(displayModel.items[0].section)
        #expect(section == "Section Title")
    }
}

@MainActor
@Suite("What's New - Modal Mapper Action Handling Tests")
struct WhatsNewDisplayModelActionHandlingTests {
    private let sut = WhatsNewDisplayModelMapper()

    @Test("Check Primary Action Invokes Correct Callbacks")
    func whenPrimaryActionInvokedThenCallbacksAreCalled() async throws {
        // GIVEN
        let expectedAction = RemoteAction.dismiss
        let message = RemoteMessageModel.makeCardsListMessage(primaryAction: expectedAction)

        var primaryActionCalled = false
        var capturedAction: RemoteAction?
        var dismissCalled = false

        let displayModel = try #require(
            sut.makeDisplayModel(
                from: message,
                onMessageAppear: { },
                onItemAppear: { _ in },
                onItemAction: { _, _ in },
                onPrimaryAction: { action in
                    primaryActionCalled = true
                    capturedAction = action
                },
                onDismiss: {
                    dismissCalled = true
                }
            )
        )

        // WHEN
        displayModel.primaryAction?.action()
        await Task.yield()

        // THEN
        #expect(primaryActionCalled)
        #expect(capturedAction == expectedAction)
        #expect(dismissCalled)
    }

    @Test("Check Item Appear Invokes Callback With Correct Item ID")
    func whenItemAppearsCallbackInvokedThenItemIdIsPassed() throws {
        // GIVEN
        let items = [
            RemoteMessageModelType.ListItem.makeTwoLinesListItem(id: "item-1"),
            RemoteMessageModelType.ListItem.makeTwoLinesListItem(id: "item-2"),
            RemoteMessageModelType.ListItem.makeTwoLinesListItem(id: "item-3")
        ]
        let message = RemoteMessageModel.makeCardsListMessage(items: items)

        var itemAppearedCalls: [String] = []

        let displayModel = try #require(
            sut.makeDisplayModel(
                from: message,
                onMessageAppear: { },
                onItemAppear: { itemId in
                    itemAppearedCalls.append(itemId)
                },
                onItemAction: { _, _ in },
                onPrimaryAction: { _ in },
                onDismiss: { }
            )
        )

        // WHEN - Invoke onAppear for each item
        displayModel.items[safe: 0]?.twoLinesCard?.onAppear?()
        displayModel.items[safe: 1]?.twoLinesCard?.onAppear?()
        displayModel.items[safe: 2]?.twoLinesCard?.onAppear?()

        // THEN
        #expect(itemAppearedCalls.count == 3)
        #expect(itemAppearedCalls[0] == "item-1")
        #expect(itemAppearedCalls[1] == "item-2")
        #expect(itemAppearedCalls[2] == "item-3")
    }

    @Test("Check Item Action Invokes Item Callback")
    func whenItemActionInvokedThenItemCallbackIsCalled() async throws {
        // GIVEN
        let expectedAction = RemoteAction.navigation(value: .importPasswords)
        let item = RemoteMessageModelType.ListItem.makeTwoLinesListItem(id: "1", action: expectedAction)
        let message = RemoteMessageModel.makeCardsListMessage(items: [item])

        var itemActionCalled = false
        var capturedAction: RemoteAction?
        var capturedItemId: String?

        let displayModel = try #require(
            sut.makeDisplayModel(
                from: message,
                onMessageAppear: { },
                onItemAppear: { _ in },
                onItemAction: { action, itemId in
                    itemActionCalled = true
                    capturedAction = action
                    capturedItemId = itemId
                },
                onPrimaryAction: { _ in },
                onDismiss: { }
            )
        )

        // WHEN
        displayModel.items.first?.twoLinesCard?.onTapAction?()
        await Task.yield()

        // THEN
        #expect(itemActionCalled)
        #expect(capturedAction == expectedAction)
        #expect(capturedItemId == "1")
    }

    @Test("Check Item Action Does Not Invoke Dismiss")
    func whenItemActionInvokedThenDismissIsNotCalled() async throws {
        // GIVEN
        let item = RemoteMessageModelType.ListItem.makeTwoLinesListItem(id: "1", action: .urlInContext(value: "https://example.com"))
        let message = RemoteMessageModel.makeCardsListMessage(items: [item])

        var itemActionCalled = false
        var dismissCalled = false

        let displayModel = try #require(
            sut.makeDisplayModel(
                from: message,
                onMessageAppear: { },
                onItemAppear: { _ in },
                onItemAction: { _, _ in
                    itemActionCalled = true
                },
                onPrimaryAction: { _ in },
                onDismiss: {
                    dismissCalled = true
                }
            )
        )

        // WHEN
        displayModel.items.first?.twoLinesCard?.onTapAction?()
        await Task.yield()

        // THEN
        #expect(itemActionCalled)
        #expect(!dismissCalled)
    }

    @Test(
        "Check Different Primary Actions Are Mapped Correctly",
        arguments: [
            RemoteAction.dismiss,
            RemoteAction.url(value: "https://example.com"),
            RemoteAction.urlInContext(value: "https://example.com"),
            RemoteAction.navigation(value: .settings),
            RemoteAction.navigation(value: .importPasswords),
            RemoteAction.share(value: "Test Value", title: "Test Title"),
            RemoteAction.appStore
        ]
    )
    func whenDifferentPrimaryActionsThenActionIsCapturedCorrectly(expectedAction: RemoteAction) async throws {
        // GIVEN
        let message = RemoteMessageModel.makeCardsListMessage(primaryAction: expectedAction)

        var capturedAction: RemoteAction?

        let displayModel = try #require(
            sut.makeDisplayModel(
                from: message,
                onMessageAppear: { },
                onItemAppear: { _ in },
                onItemAction: { _, _ in },
                onPrimaryAction: { action in
                    capturedAction = action
                },
                onDismiss: { }
            )
        )

        // WHEN
        displayModel.primaryAction?.action()
        await Task.yield()

        // THEN
        #expect(capturedAction == expectedAction)
    }

    @Test("Check Multiple Action Invocations On Item Works Correctly")
    func whenActionInvokedMultipleTimesThenCallbackIsCalledEachTime() async throws {
        // GIVEN
        let item = RemoteMessageModelType.ListItem.makeTwoLinesListItem(id: "1", action: .url(value: "https://example.com"))
        let message = RemoteMessageModel.makeCardsListMessage(items: [item])

        var callCount = 0

        let displayModel = try #require(sut.makeDisplayModel(
            from: message,
            onMessageAppear: { },
            onItemAppear: { _ in },
            onItemAction: { _, _ in
                callCount += 1
            },
            onPrimaryAction: { _ in },
            onDismiss: { }
        ))

        // WHEN
        displayModel.items.first?.twoLinesCard?.onTapAction?()
        await Task.yield()

        displayModel.items.first?.twoLinesCard?.onTapAction?()
        await Task.yield()

        displayModel.items.first?.twoLinesCard?.onTapAction?()
        await Task.yield()

        // THEN
        #expect(callCount == 3)
    }
}

private extension RemoteMessagingUI.CardsListDisplayModel.Item {

    var twoLinesCard: RemoteMessagingUI.CardsListDisplayModel.Item.TwoLinesCard? {
        switch self {
        case .twoLinesCard(let card):
            return card
        case .section:
            return nil
        }
    }

    var section: String? {
        switch self {
        case .section(let title):
            return title
        case .twoLinesCard:
            return nil
        }
    }

}
