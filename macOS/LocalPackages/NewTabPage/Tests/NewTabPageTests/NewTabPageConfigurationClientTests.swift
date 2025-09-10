//
//  NewTabPageConfigurationClientTests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import AppKit
import Combine
import XCTest
@testable import NewTabPage
import BrowserServicesKit

final class NewTabPageConfigurationClientTests: XCTestCase {
    private var client: NewTabPageConfigurationClient!
    private var sectionsAvailabilityProvider: MockNewTabPageSectionsAvailabilityProvider!
    private var sectionsVisibilityProvider: MockNewTabPageSectionsVisibilityProvider!
    private var omnibarConfigProvider: MockNewTabPageOmnibarConfigProvider!
    private var contextMenuPresenter: CapturingNewTabPageContextMenuPresenter!
    private var userScript: NewTabPageUserScript!
    private var messageHelper: MessageHelper<NewTabPageConfigurationClient.MessageName>!
    private var eventMapper: CapturingNewTabPageConfigurationEventHandler!

    override func setUpWithError() throws {
        try super.setUpWithError()
        sectionsVisibilityProvider = MockNewTabPageSectionsVisibilityProvider()
        sectionsAvailabilityProvider = MockNewTabPageSectionsAvailabilityProvider()
        omnibarConfigProvider = MockNewTabPageOmnibarConfigProvider()
        contextMenuPresenter = CapturingNewTabPageContextMenuPresenter()
        eventMapper = CapturingNewTabPageConfigurationEventHandler()
        client = NewTabPageConfigurationClient(
            sectionsAvailabilityProvider: sectionsAvailabilityProvider,
            sectionsVisibilityProvider: sectionsVisibilityProvider,
            omnibarConfigProvider: omnibarConfigProvider,
            customBackgroundProvider: CapturingNewTabPageCustomBackgroundProvider(),
            contextMenuPresenter: contextMenuPresenter,
            linkOpener: CapturingNewTabPageLinkOpener(),
            eventMapper: eventMapper
        )

        userScript = NewTabPageUserScript()
        messageHelper = .init(userScript: userScript)
        client.registerMessageHandlers(for: userScript)
    }

    // MARK: - contextMenu

    @MainActor
    func testShowContextMenu_ShowsAllItems_WhenAllFeaturesAreAvailable() async throws {
        sectionsAvailabilityProvider.isOmnibarAvailable = true
        sectionsVisibilityProvider.isOmnibarVisible = true
        sectionsVisibilityProvider.isFavoritesVisible = true
        sectionsVisibilityProvider.isProtectionsReportVisible = true
        omnibarConfigProvider.isAIChatSettingVisible = true
        omnibarConfigProvider.isAIChatShortcutEnabled = true

        let parameters = NewTabPageDataModel.ContextMenuParams(visibilityMenuItems: [])
        try await messageHelper.handleMessageExpectingNilResponse(named: .contextMenu, parameters: parameters)

        let menu = try XCTUnwrap(contextMenuPresenter.showContextMenuCalls.first)
        let itemTitles = menu.items.map(\.title)

        XCTAssertTrue(itemTitles.contains(UserText.newTabPageContextMenuSearch))
        XCTAssertTrue(itemTitles.contains(UserText.newTabPageContextMenuFavorites))
        XCTAssertTrue(itemTitles.contains(UserText.newTabPageContextMenuProtectionsReport))
        XCTAssertTrue(itemTitles.contains(UserText.newTabPageContextMenuShowDuckAI))
        XCTAssertTrue(itemTitles.contains(UserText.newTabPageContextMenuOpenDuckAISettings))
    }

    @MainActor
    func testShowContextMenu_HidesAIOptions_WhenAISettingNotVisible() async throws {
        sectionsAvailabilityProvider.isOmnibarAvailable = true
        sectionsVisibilityProvider.isOmnibarVisible = true
        sectionsVisibilityProvider.isFavoritesVisible = true
        sectionsVisibilityProvider.isProtectionsReportVisible = true
        omnibarConfigProvider.isAIChatSettingVisible = false
        omnibarConfigProvider.isAIChatShortcutEnabled = true

        let parameters = NewTabPageDataModel.ContextMenuParams(visibilityMenuItems: [])
        try await messageHelper.handleMessageExpectingNilResponse(named: .contextMenu, parameters: parameters)

        let menu = try XCTUnwrap(contextMenuPresenter.showContextMenuCalls.first)
        let itemTitles = menu.items.map(\.title)

        XCTAssertFalse(itemTitles.contains(UserText.newTabPageContextMenuShowDuckAI))
        XCTAssertFalse(itemTitles.contains(UserText.newTabPageContextMenuOpenDuckAISettings))
    }

    @MainActor
    func testShowContextMenu_ShowsJustFavoritesAndProtections_WhenAllFlagsAreDisabledOrHidden() async throws {
        sectionsAvailabilityProvider.isOmnibarAvailable = false
        sectionsVisibilityProvider.isOmnibarVisible = false
        sectionsVisibilityProvider.isFavoritesVisible = false
        sectionsVisibilityProvider.isProtectionsReportVisible = false
        omnibarConfigProvider.isAIChatSettingVisible = false
        omnibarConfigProvider.isAIChatShortcutEnabled = false

        let parameters = NewTabPageDataModel.ContextMenuParams(visibilityMenuItems: [])
        try await messageHelper.handleMessageExpectingNilResponse(named: .contextMenu, parameters: parameters)

        let menu = try XCTUnwrap(contextMenuPresenter.showContextMenuCalls.first)
        let itemTitles = menu.items.map(\.title)
        XCTAssertFalse(itemTitles.contains(UserText.newTabPageContextMenuSearch))
        XCTAssertTrue(itemTitles.contains(UserText.newTabPageContextMenuFavorites))
        XCTAssertTrue(itemTitles.contains(UserText.newTabPageContextMenuProtectionsReport))
        XCTAssertFalse(itemTitles.contains(UserText.newTabPageContextMenuShowDuckAI))
        XCTAssertFalse(itemTitles.contains(UserText.newTabPageContextMenuOpenDuckAISettings))
    }

    // MARK: - initialSetup

    func testThatInitialSetupReturnsConfiguration() async throws {
        sectionsAvailabilityProvider.isOmnibarAvailable = true

        let configuration: NewTabPageDataModel.NewTabPageConfiguration = try await messageHelper.handleMessage(named: .initialSetup)
        XCTAssertEqual(configuration.widgets, [
            .init(id: .rmf),
            .init(id: .freemiumPIRBanner),
            .init(id: .omnibar),
            .init(id: .nextSteps),
            .init(id: .favorites),
            .init(id: .protections)
        ])
        XCTAssertEqual(configuration.widgetConfigs, [
            .init(id: .favorites, isVisible: sectionsVisibilityProvider.isFavoritesVisible),
            .init(id: .protections, isVisible: sectionsVisibilityProvider.isProtectionsReportVisible),
            .init(id: .omnibar, isVisible: sectionsVisibilityProvider.isOmnibarVisible)
        ])
        XCTAssertEqual(configuration.platform, .init(name: "macos"))
    }

    func testWhenOmnibarNotAvailable_ThenInitialSetupReturnsConfigurationWithoutOmnibar() async throws {
        sectionsAvailabilityProvider.isOmnibarAvailable = false

        let configuration: NewTabPageDataModel.NewTabPageConfiguration = try await messageHelper.handleMessage(named: .initialSetup)
        XCTAssertEqual(configuration.widgets, [
            .init(id: .rmf),
            .init(id: .freemiumPIRBanner),
            .init(id: .nextSteps),
            .init(id: .favorites),
            .init(id: .protections),
        ])
        XCTAssertEqual(configuration.widgetConfigs, [
            .init(id: .favorites, isVisible: sectionsVisibilityProvider.isFavoritesVisible),
            .init(id: .protections, isVisible: sectionsVisibilityProvider.isProtectionsReportVisible),
        ])
        XCTAssertEqual(configuration.platform, .init(name: "macos"))
    }

    // MARK: - widgetsSetConfig

    func testWhenWidgetsSetConfigIsReceivedThenWidgetConfigsAreUpdated() async throws {
        let configs: [NewTabPageDataModel.NewTabPageConfiguration.WidgetConfig] = [
            .init(id: .favorites, isVisible: false),
            .init(id: .protections, isVisible: true)
        ]
        try await messageHelper.handleMessageExpectingNilResponse(named: .widgetsSetConfig, parameters: configs)
        XCTAssertEqual(sectionsVisibilityProvider.isFavoritesVisible, false)
        XCTAssertEqual(sectionsVisibilityProvider.isProtectionsReportVisible, true)
    }

    func testWhenWidgetsSetConfigIsReceivedWithPartialConfigThenOnlyIncludedWidgetsConfigsAreUpdated() async throws {
        let initialIsFavoritesVisible = sectionsVisibilityProvider.isFavoritesVisible

        let configs: [NewTabPageDataModel.NewTabPageConfiguration.WidgetConfig] = [
            .init(id: .protections, isVisible: false),
        ]
        try await messageHelper.handleMessageExpectingNilResponse(named: .widgetsSetConfig, parameters: configs)
        XCTAssertEqual(sectionsVisibilityProvider.isFavoritesVisible, initialIsFavoritesVisible)
        XCTAssertEqual(sectionsVisibilityProvider.isProtectionsReportVisible, false)
    }

    // MARK: - reportInitException

    func testThatReportInitExceptionForwardsEventToTheMapper() async throws {
        let exception = NewTabPageDataModel.Exception(message: "sample message")
        try await messageHelper.handleMessageExpectingNilResponse(named: .reportInitException, parameters: exception)

        XCTAssertEqual(eventMapper.events, [.newTabPageError(message: "sample message")])
    }

    // MARK: - reportPageException

    func testThatReportPageExceptionForwardsEventToTheMapper() async throws {
        let exception = NewTabPageDataModel.Exception(message: "sample message")
        try await messageHelper.handleMessageExpectingNilResponse(named: .reportPageException, parameters: exception)

        XCTAssertEqual(eventMapper.events, [.newTabPageError(message: "sample message")])
    }
}
