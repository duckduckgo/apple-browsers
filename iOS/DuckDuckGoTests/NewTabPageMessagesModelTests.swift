//
//  NewTabPageMessagesModelTests.swift
//  DuckDuckGo
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

import Combine
import Core
import RemoteMessaging
import XCTest
import DDGSync

@testable import DuckDuckGo

@MainActor
final class NewTabPageMessagesModelTests: XCTestCase {
 
    private var messagesConfiguration: HomePageMessagesConfigurationMock!
    private var notificationCenter: NotificationCenter!

    private var segueToAIChatSettingsCallCount = 0
    private var segueToSettingsCallCount = 0
    private var segueToSettingsGeneralCallCount = 0
    private var segueToFeedbackCallCount = 0
    private var segueToSyncSettingsCallCount = 0
    private var segueToSettingsAppearanceCallCount = 0
    private var segueToPIRCallCount = 0

    override func setUpWithError() throws {
        messagesConfiguration = HomePageMessagesConfigurationMock(homeMessages: [])
        notificationCenter = NotificationCenter()
        segueToAIChatSettingsCallCount = 0
        segueToSettingsCallCount = 0
        segueToSettingsGeneralCallCount = 0
        segueToFeedbackCallCount = 0
        segueToSyncSettingsCallCount = 0
        segueToSettingsAppearanceCallCount = 0
        segueToPIRCallCount = 0
    }

    override func tearDownWithError() throws {
        PixelFiringMock.tearDown()
    }

    func testUpdatesOnNotification() {
        let sut = createSUT()

        sut.load()

        XCTAssertTrue(sut.homeMessageViewModels.isEmpty)

        messagesConfiguration.homeMessages = [.placeholder]

        notificationCenter.post(name: RemoteMessagingStore.Notifications.remoteMessagesDidChange,
                                object: nil)

        XCTAssertEqual(sut.homeMessageViewModels.count, 1)
    }

    func testCoordinatedLoadReadsSharedSourceWithoutRefreshingOrEagerAppearance() throws {
        let message = HomeMessage.mockRemote(withType: .small(titleText: "Title", descriptionText: "Description"))
        let configuration = CoordinatedMessagesConfigurationMock(homeMessages: [message])
        let sut = createSUT(configuration: configuration)

        sut.load()

        XCTAssertEqual(configuration.refreshCallCount, 0)
        XCTAssertEqual(configuration.didAppearCallCount, 0)
        let viewModel = try XCTUnwrap(sut.homeMessageViewModels.first)
        XCTAssertEqual(viewModel.acquisitionIdentity, configuration.presentationContext.acquisitionIdentity)
    }

    func testCoordinatedSignalSynchronouslyConvergesTwoModelsWithoutGlobalNotification() {
        let configuration = CoordinatedMessagesConfigurationMock(homeMessages: [])
        let first = createSUT(configuration: configuration)
        let second = createSUT(configuration: configuration)
        first.load()
        second.load()

        configuration.homeMessages = [.placeholder]
        configuration.sendContentDidChange()

        XCTAssertEqual(first.homeMessageViewModels.count, 1)
        XCTAssertEqual(second.homeMessageViewModels.count, 1)
        XCTAssertEqual(configuration.refreshCallCount, 0)

        configuration.homeMessages = []
        notificationCenter.post(name: RemoteMessagingStore.Notifications.remoteMessagesDidChange, object: nil)

        XCTAssertEqual(first.homeMessageViewModels.count, 1)
        XCTAssertEqual(second.homeMessageViewModels.count, 1)
    }

    func testCoordinatedSignalRemovesLastRenderedMessage() {
        let configuration = CoordinatedMessagesConfigurationMock(homeMessages: [.placeholder])
        let sut = createSUT(configuration: configuration)
        sut.load()

        configuration.homeMessages = []
        configuration.sendContentDidChange()

        XCTAssertTrue(sut.homeMessageViewModels.isEmpty)
    }

    func testLegacyDismissRemovesLastRenderedMessage() async throws {
        let message = HomeMessage.mockRemote(withType: .small(titleText: "Title", descriptionText: "Description"))
        let configuration = DismissingLegacyMessagesConfigurationMock(homeMessages: [message])
        let sut = createSUT(configuration: configuration)
        sut.load()
        let viewModel = try XCTUnwrap(sut.homeMessageViewModels.first)

        await viewModel.onDidClose(.close)

        XCTAssertTrue(sut.homeMessageViewModels.isEmpty)
    }

    func testCoordinatedCallbacksRoundTripCapturedPresentationContext() async throws {
        let message = HomeMessage.mockRemote(withType: .small(titleText: "Title", descriptionText: "Description"))
        let configuration = CoordinatedMessagesConfigurationMock(homeMessages: [message])
        let sut = createSUT(configuration: configuration)
        sut.load()
        let viewModel = try XCTUnwrap(sut.homeMessageViewModels.first)

        viewModel.onDidAppear()
        await viewModel.onDidClose(.close)

        XCTAssertEqual(configuration.lastAppearedContext, configuration.presentationContext)
        XCTAssertEqual(configuration.lastDismissedContext, configuration.presentationContext)
        XCTAssertEqual(configuration.didAppearCallCount, 1)
        XCTAssertEqual(configuration.dismissCallCount, 1)
    }

    // MARK: Callbacks

    func testCallsDismissOnClose() async throws {
        let sut = createSUT()
        messagesConfiguration.homeMessages = [
            .mockRemote(withType: .small(titleText: "", descriptionText: "")),
        ]
        sut.load()

        let model = try XCTUnwrap(sut.homeMessageViewModels.first)

        await model.onDidClose(.close)

        XCTAssertEqual(messagesConfiguration.lastDismissedHomeMessage, messagesConfiguration.homeMessages.first)
    }

    func testCallsDismissOnAction() async throws {
        let sut = createSUT()
        messagesConfiguration.homeMessages = [
            .mockRemote(withType: .small(titleText: "", descriptionText: "")),
        ]
        sut.load()

        let model = try XCTUnwrap(sut.homeMessageViewModels.first)

        await model.onDidClose(.action(isShare: false))

        XCTAssertEqual(messagesConfiguration.lastDismissedHomeMessage, messagesConfiguration.homeMessages.first)
    }

    func testCallsDismissOnPrimaryAction() async throws {
        let sut = createSUT()
        messagesConfiguration.homeMessages = [
            .mockRemote(withType: .small(titleText: "", descriptionText: "")),
        ]
        sut.load()

        let model = try XCTUnwrap(sut.homeMessageViewModels.first)

        await model.onDidClose(.primaryAction(isShare: false))

        XCTAssertEqual(messagesConfiguration.lastDismissedHomeMessage, messagesConfiguration.homeMessages.first)
    }

    func testCallsDismissOnSecondaryAction() async throws {
        let sut = createSUT()
        messagesConfiguration.homeMessages = [
            .mockRemote(withType: .small(titleText: "", descriptionText: "")),
        ]
        sut.load()

        let model = try XCTUnwrap(sut.homeMessageViewModels.first)

        await model.onDidClose(.secondaryAction(isShare: false))

        XCTAssertEqual(messagesConfiguration.lastDismissedHomeMessage, messagesConfiguration.homeMessages.first)
    }

    func testDoesNotCallDismissWhenSharing() async throws {
        let sut = createSUT()
        messagesConfiguration.homeMessages = [
            .mockRemote(withType: .small(titleText: "", descriptionText: "")),
        ]
        sut.load()

        let model = try XCTUnwrap(sut.homeMessageViewModels.first)

        await model.onDidClose(.action(isShare: true))
        await model.onDidClose(.primaryAction(isShare: true))
        await model.onDidClose(.secondaryAction(isShare: true))

        XCTAssertNil(messagesConfiguration.lastDismissedHomeMessage)
    }

    func testMessageNavigator() async throws {

        func assertSegueCount(_ count: Int) {
            XCTAssertEqual(segueToSettingsCallCount, count)
            XCTAssertEqual(segueToSettingsGeneralCallCount, count)
            XCTAssertEqual(segueToAIChatSettingsCallCount, count)
            XCTAssertEqual(segueToFeedbackCallCount, count)
            XCTAssertEqual(segueToSettingsAppearanceCallCount, count)
            XCTAssertEqual(segueToPIRCallCount, count)
        }

        // Start state
        assertSegueCount(0)

        // Individual states
        DefaultMessageNavigator(delegate: self).navigateTo(.settings, presentationStyle: .dismissModalsAndPresentFromRoot)
        XCTAssertEqual(segueToSettingsCallCount, 1)

        DefaultMessageNavigator(delegate: self).navigateTo(.settingsGeneral, presentationStyle: .dismissModalsAndPresentFromRoot)
        XCTAssertEqual(segueToSettingsGeneralCallCount, 1)

        DefaultMessageNavigator(delegate: self).navigateTo(.duckAISettings, presentationStyle: .dismissModalsAndPresentFromRoot)
        XCTAssertEqual(segueToAIChatSettingsCallCount, 1)
        
        DefaultMessageNavigator(delegate: self).navigateTo(.feedback, presentationStyle: .dismissModalsAndPresentFromRoot)
        XCTAssertEqual(segueToFeedbackCallCount, 1)

        DefaultMessageNavigator(delegate: self).navigateTo(.appearance, presentationStyle: .dismissModalsAndPresentFromRoot)
        XCTAssertEqual(segueToSettingsAppearanceCallCount, 1)

        DefaultMessageNavigator(delegate: self).navigateTo(.personalInformationRemoval, presentationStyle: .dismissModalsAndPresentFromRoot)
        XCTAssertEqual(segueToPIRCallCount, 1)

        // End state
        assertSegueCount(1)

    }

    // MARK: Pixels

    func testFiresPixelOnClose() async throws {
        let sut = createSUT()
        messagesConfiguration.homeMessages = [
            .mockRemote(withType: .small(titleText: "", descriptionText: "")),
        ]
        sut.load()

        let model = try XCTUnwrap(sut.homeMessageViewModels.first)

        await model.onDidClose(.close)

        XCTAssertEqual(PixelFiringMock.lastPixelName, Pixel.Event.remoteMessageDismissed.name)
        XCTAssertEqual(PixelFiringMock.lastParams, [PixelParameters.message: "foo"])
    }

    func testFiresPixelOnAction() async throws {
        let sut = createSUT()
        messagesConfiguration.homeMessages = [
            .mockRemote(withType: .small(titleText: "", descriptionText: "")),
        ]
        sut.load()

        let model = try XCTUnwrap(sut.homeMessageViewModels.first)
        await model.onDidClose(.action(isShare: false))

        XCTAssertEqual(PixelFiringMock.lastPixelName, Pixel.Event.remoteMessageActionClicked.name)
        XCTAssertEqual(PixelFiringMock.lastParams, [PixelParameters.message: "foo"])
    }

    func testFiresPixelOnPrimaryAction() async throws {
        let sut = createSUT()
        messagesConfiguration.homeMessages = [
            .mockRemote(withType: .small(titleText: "", descriptionText: "")),
        ]
        sut.load()

        let model = try XCTUnwrap(sut.homeMessageViewModels.first)
        await model.onDidClose(.primaryAction(isShare: false))

        XCTAssertEqual(PixelFiringMock.lastPixelName, Pixel.Event.remoteMessagePrimaryActionClicked.name)
        XCTAssertEqual(PixelFiringMock.lastParams, [PixelParameters.message: "foo"])
    }

    func testFiresPixelOnSecondaryAction() async throws {
        let sut = createSUT()
        messagesConfiguration.homeMessages = [
            .mockRemote(withType: .small(titleText: "", descriptionText: "")),
        ]
        sut.load()

        let model = try XCTUnwrap(sut.homeMessageViewModels.first)
        await model.onDidClose(.secondaryAction(isShare: false))

        XCTAssertEqual(PixelFiringMock.lastPixelName, Pixel.Event.remoteMessageSecondaryActionClicked.name)
        XCTAssertEqual(PixelFiringMock.lastParams, [PixelParameters.message: "foo"])
    }

    func testDoesNotFirePixelOnCloseWhenMetricsAreDisabled() async throws {
        let sut = createSUT()
        messagesConfiguration.homeMessages = [
            .mockRemote(withType: .small(titleText: "", descriptionText: ""), isMetricsEnabled: false),
        ]
        sut.load()

        let model = try XCTUnwrap(sut.homeMessageViewModels.first)

        await model.onDidClose(.close)

        XCTAssertNil(PixelFiringMock.lastPixelName)
        XCTAssertNil(PixelFiringMock.lastParams)
    }

    func testDoesNotFirePixelOnActionWhenMetricsAreDisabled() async throws {
        let sut = createSUT()
        messagesConfiguration.homeMessages = [
            .mockRemote(withType: .small(titleText: "", descriptionText: ""), isMetricsEnabled: false),
        ]
        sut.load()

        let model = try XCTUnwrap(sut.homeMessageViewModels.first)
        await model.onDidClose(.action(isShare: false))

        XCTAssertNil(PixelFiringMock.lastPixelName)
        XCTAssertNil(PixelFiringMock.lastParams)
    }

    func testDoesNotFirePixelOnPrimaryActionWhenMetricsAreDisabled() async throws {
        let sut = createSUT()
        messagesConfiguration.homeMessages = [
            .mockRemote(withType: .small(titleText: "", descriptionText: ""), isMetricsEnabled: false),
        ]
        sut.load()

        let model = try XCTUnwrap(sut.homeMessageViewModels.first)
        await model.onDidClose(.primaryAction(isShare: false))

        XCTAssertNil(PixelFiringMock.lastPixelName)
        XCTAssertNil(PixelFiringMock.lastParams)
    }

    func testDoesNotFirePixelOnSecondaryActionWhenMetricsAreDisabled() async throws {
        let sut = createSUT()
        messagesConfiguration.homeMessages = [
            .mockRemote(withType: .small(titleText: "", descriptionText: ""), isMetricsEnabled: false),
        ]
        sut.load()

        let model = try XCTUnwrap(sut.homeMessageViewModels.first)
        await model.onDidClose(.secondaryAction(isShare: false))

        XCTAssertNil(PixelFiringMock.lastPixelName)
        XCTAssertNil(PixelFiringMock.lastParams)
    }

    // MARK: - openedAfterIdle

    func testWhenOpenedAfterIdleIsTrueThenRefreshPassesOpenedAfterIdleTrue() {
        let sut = createSUT(isOpenedAfterIdle: true)

        sut.load()

        XCTAssertTrue(messagesConfiguration.didRefresh)
        XCTAssertEqual(messagesConfiguration.lastRefreshOpenedAfterIdle, true)
    }

    func testWhenOpenedAfterIdleIsFalseThenRefreshPassesOpenedAfterIdleFalse() {
        let sut = createSUT(isOpenedAfterIdle: false)

        sut.load()

        XCTAssertTrue(messagesConfiguration.didRefresh)
        XCTAssertEqual(messagesConfiguration.lastRefreshOpenedAfterIdle, false)
    }

    func testWhenDefaultOpenedAfterIdleThenRefreshPassesFalse() {
        let sut = createSUT()

        sut.load()

        XCTAssertTrue(messagesConfiguration.didRefresh)
        XCTAssertEqual(messagesConfiguration.lastRefreshOpenedAfterIdle, false)
    }

    // MARK: - Helpers

    private func createSUT(isOpenedAfterIdle: Bool = false) -> NewTabPageMessagesModel {
        createSUT(configuration: messagesConfiguration, isOpenedAfterIdle: isOpenedAfterIdle)
    }

    private func createSUT(
        configuration: HomePageMessagesConfiguration,
        isOpenedAfterIdle: Bool = false
    ) -> NewTabPageMessagesModel {
        let remoteMessageActionHandler = RemoteMessagingActionHandler(surveyUsageStateRefresher: RemoteMessagingSurveyUsageStateRefresher())
        remoteMessageActionHandler.messageNavigator = DefaultMessageNavigator(delegate: self)

        return NewTabPageMessagesModel(homePageMessagesConfiguration: configuration,
                                notificationCenter: notificationCenter,
                                pixelFiring: PixelFiringMock.self,
                                messageActionHandler: remoteMessageActionHandler,
                                imageLoader: MockRemoteMessagingImageLoader(),
                                isOpenedAfterIdle: { isOpenedAfterIdle })
    }
}

@MainActor
private final class DismissingLegacyMessagesConfigurationMock: HomePageMessagesConfigurationMock {
    override func dismissHomeMessage(_ homeMessage: HomeMessage) {
        super.dismissHomeMessage(homeMessage)
        homeMessages.removeAll { $0 == homeMessage }
    }
}

@MainActor
private final class CoordinatedMessagesConfigurationMock: HomePageMessagesConfiguration {
    let mode = PromoCoordinationMode.coordinated
    let presentationContext: HomeMessagePresentationContext
    var homeMessages: [HomeMessage]

    private let contentDidChangeSubject = PassthroughSubject<Void, Never>()
    private let arbiterLease: PromoQueueRemoteMessageArbiterLease

    private(set) var refreshCallCount = 0
    private(set) var didAppearCallCount = 0
    private(set) var dismissCallCount = 0
    private(set) var lastAppearedContext: HomeMessagePresentationContext?
    private(set) var lastDismissedContext: HomeMessagePresentationContext?

    var contentDidChangePublisher: AnyPublisher<Void, Never> {
        contentDidChangeSubject.eraseToAnyPublisher()
    }

    init(homeMessages: [HomeMessage]) {
        self.homeMessages = homeMessages
        let arbiter = PromoQueueLeaseArbiter()
        guard case .acquired(let arbiterLease) = arbiter.acquireRemoteMessageLease(for: "foo") else {
            fatalError("Expected the test arbiter to grant its first RMF acquisition")
        }
        self.arbiterLease = arbiterLease
        presentationContext = HomeMessagePresentationContext(
            messageID: "foo",
            acquisitionIdentity: arbiterLease.acquisitionIdentity
        )
    }

    func sendContentDidChange() {
        contentDidChangeSubject.send(())
    }

    func refresh(openedAfterIdle: Bool) {
        refreshCallCount += 1
    }

    func dismissHomeMessage(_ homeMessage: HomeMessage) async {}

    func dismissHomeMessage(_ homeMessage: HomeMessage, presentationContext: HomeMessagePresentationContext?) async {
        dismissCallCount += 1
        lastDismissedContext = presentationContext
    }

    func didAppear(_ homeMessage: HomeMessage) {}

    func didAppear(_ homeMessage: HomeMessage, presentationContext: HomeMessagePresentationContext?) {
        didAppearCallCount += 1
        lastAppearedContext = presentationContext
    }

    func presentationContext(for homeMessage: HomeMessage) -> HomeMessagePresentationContext? {
        presentationContext
    }
}

extension NewTabPageMessagesModelTests: MessageNavigationDelegate {

    func segueToSettingsAIChat(openedFromSERPSettingsButton: Bool, presentationStyle: PresentationContext.Style) {
        segueToAIChatSettingsCallCount += 1
    }
    
    func segueToSettings(presentationStyle: PresentationContext.Style) {
        segueToSettingsCallCount += 1
    }

    func segueToSettingsGeneral(presentationStyle: PresentationContext.Style) {
        segueToSettingsGeneralCallCount += 1
    }

    func segueToFeedback(presentationStyle: PresentationContext.Style) {
        segueToFeedbackCallCount += 1
    }

    func segueToSettingsSync(with source: String?, pairingInfo: PairingInfo?, presentationStyle: PresentationContext.Style) {
        segueToSyncSettingsCallCount += 1
    }

    func segueToImportPasswords(presentationStyle: DuckDuckGo.PresentationContext.Style) {
        assertionFailure("Not implemented yet")
    }

    func segueToSettingsAppearance(presentationStyle: PresentationContext.Style) {
        segueToSettingsAppearanceCallCount += 1
    }

    func segueToPIR(presentationStyle: DuckDuckGo.PresentationContext.Style) {
        segueToPIRCallCount += 1
    }

}

private extension HomeMessage {
    static func mockRemote(withType type: RemoteMessageModelType, isMetricsEnabled: Bool = true) -> Self {
        HomeMessage.remoteMessage(
            remoteMessage: .init(
                id: "foo",
                surfaces: .newTabPage,
                content: type,
                matchingRules: [],
                exclusionRules: [],
                isMetricsEnabled: isMetricsEnabled
            )
        )
    }
}
