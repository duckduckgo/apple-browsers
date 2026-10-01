//
//  LaunchActionHandlerTests.swift
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

import UIKit
import Testing
import Core
import FeatureFlags_iOS
@testable import DuckDuckGo
@_spi(Testing) import PixelKit

final class MockURLHandler: URLHandling {

    var handleURLCalled = false
    var lastHandledURL: URL?
    var shouldProcessDeepLinkResult = true

    func handleURL(_ url: URL) {
        handleURLCalled = true
        lastHandledURL = url
    }

    func shouldProcessDeepLink(_ url: URL) -> Bool {
        shouldProcessDeepLinkResult
    }

}

final class MockShortcutItemHandler: ShortcutItemHandling {

    var handleShortcutItemCalled = false
    var lastHandledShortcutItem: UIApplicationShortcutItem?

    func handleShortcutItem(_ item: UIApplicationShortcutItem) {
        handleShortcutItemCalled = true
        lastHandledShortcutItem = item
    }

}

final class MockUserActivityHandler: UserActivityHandling {

    var handleUserActivityCalled = false
    var lastHandledUserActivity: NSUserActivity?
    var handleUserActivityResult = true

    @discardableResult
    func handleUserActivity(_ userActivity: NSUserActivity) -> Bool {
        handleUserActivityCalled = true
        lastHandledUserActivity = userActivity
        return handleUserActivityResult
    }

}

final class MockKeyboardPresenter: KeyboardPresenting {

    var showKeyboardOnLaunchCalled = false
    var lastBackgroundDate: Date?
    var isAfterIdleReturn = false

    func showKeyboardOnLaunch(lastBackgroundDate: Date?, isAfterIdleReturn: Bool) {
        showKeyboardOnLaunchCalled = true
        self.lastBackgroundDate = lastBackgroundDate
        self.isAfterIdleReturn = isAfterIdleReturn
    }

}

final class MockIdleReturnEvaluator: IdleReturnEvaluating {
    var didReturnAfterIdleResult = false
    var treatmentForIdleReturnResult: IdleReturnTreatment = .ntp
    var lastLastBackgroundDate: Date?

    func didReturnAfterIdle(lastBackgroundDate: Date?) -> Bool {
        lastLastBackgroundDate = lastBackgroundDate
        return didReturnAfterIdleResult
    }

    func treatmentForIdleReturn() -> IdleReturnTreatment {
        return treatmentForIdleReturnResult
    }
}

@MainActor
final class MockIdleReturnLaunchDelegate: IdleReturnLaunchDelegate {
    var showNewTabPageAfterIdleReturnCalled = false
    var showNewTabPageAfterIdleReturnResult = false
    var markLastUsedTabAsResumedAfterIdleCalled = false
    var recordOrdinaryReturnCalled = false

    func recordOrdinaryReturn(timeAwayMs: Int?) {
        recordOrdinaryReturnCalled = true
    }

    func showNewTabPageAfterIdleReturn(timeAwayMs: Int?) -> Bool {
        showNewTabPageAfterIdleReturnCalled = true
        return showNewTabPageAfterIdleReturnResult
    }

    func markLastUsedTabAsResumedAfterIdle(timeAwayMs: Int?) {
        markLastUsedTabAsResumedAfterIdleCalled = true
    }
}

@MainActor
final class LaunchActionHandlerTests {

    let urlHandler = MockURLHandler()
    let shortcutItemHandler = MockShortcutItemHandler()
    let userActivityHandler = MockUserActivityHandler()
    let keyboardPresenter = MockKeyboardPresenter()
    let launchSourceManager = MockLaunchSourceManager()
    let idleReturnEvaluator = MockIdleReturnEvaluator()
    let idleReturnDelegate = MockIdleReturnLaunchDelegate()
    let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [])
    let pixelKitMock = PixelKitMock()
    lazy var launchActionHandler = LaunchActionHandler(
        urlHandler: urlHandler,
        shortcutItemHandler: shortcutItemHandler,
        userActivityHandler: userActivityHandler,
        keyboardPresenter: keyboardPresenter,
        launchSourceService: launchSourceManager,
        idleReturnEvaluator: idleReturnEvaluator,
        featureFlagger: featureFlagger,
        idleReturnDelegate: idleReturnDelegate,
        pixelFiring: pixelKitMock
    )

    @Test("Open URL when LaunchAction is .openURL")
    func openURL() {
        let url = URL(string: "https://example.com")!
        let action = LaunchAction.openURL(url)

        launchActionHandler.handleLaunchAction(action)

        #expect(urlHandler.handleURLCalled)
        #expect(urlHandler.lastHandledURL == url)
    }

    @Test("Do not open URL when shouldProcessDeepLink returns false")
    func doNotOpenURLWhenShouldProcessDeepLinkReturnsFalse() {
        let url = URL(string: "https://example.com")!
        let action = LaunchAction.openURL(url)

        urlHandler.shouldProcessDeepLinkResult = false

        launchActionHandler.handleLaunchAction(action)

        #expect(!urlHandler.handleURLCalled)
    }

    @Test("Handle shortcut item when LaunchAction is .handleShortcutItem")
    func handleShortcutItem() {
        let shortcutItem = UIApplicationShortcutItem(type: "TestType", localizedTitle: "Test")
        let action = LaunchAction.handleShortcutItem(shortcutItem)

        launchActionHandler.handleLaunchAction(action)

        #expect(shortcutItemHandler.handleShortcutItemCalled)
        #expect(shortcutItemHandler.lastHandledShortcutItem == shortcutItem)
    }

    @available(iOS 16, *)
    @Test("Handle user activity when LaunchAction is .handleUserActivity", .timeLimit(.minutes(1)))
    func handleUserActivity() {
        let userActivity = NSUserActivity(activityType: "BEBrowserDataExchangeImportActivity")
        let action = LaunchAction.handleUserActivity(userActivity)

        launchActionHandler.handleLaunchAction(action)

        #expect(userActivityHandler.handleUserActivityCalled)
        #expect(userActivityHandler.lastHandledUserActivity?.activityType == userActivity.activityType)
    }

    @Test("Show keyboard when LaunchAction is .standardLaunch")
    func showKeyboard() {
        let date = Date()
        let action = LaunchAction.standardLaunch(lastBackgroundDate: date, isFirstForeground: false)

        launchActionHandler.handleLaunchAction(action)

        #expect(keyboardPresenter.showKeyboardOnLaunchCalled)
        #expect(keyboardPresenter.lastBackgroundDate == date)
    }

    @available(iOS 16, *)
    @Test("Record ordinary return when a standard launch is not after idle", .timeLimit(.minutes(1)))
    func recordOrdinaryReturnWhenNotAfterIdle() {
        idleReturnEvaluator.didReturnAfterIdleResult = false

        launchActionHandler.handleLaunchAction(.standardLaunch(lastBackgroundDate: Date(), isFirstForeground: false))

        #expect(idleReturnDelegate.recordOrdinaryReturnCalled)
    }

    @available(iOS 16, *)
    @Test("Do not record ordinary return when the return is after idle", .timeLimit(.minutes(1)))
    func noOrdinaryReturnWhenAfterIdle() {
        idleReturnEvaluator.didReturnAfterIdleResult = true
        idleReturnEvaluator.treatmentForIdleReturnResult = .ntp

        launchActionHandler.handleLaunchAction(.standardLaunch(lastBackgroundDate: Date(), isFirstForeground: false))

        #expect(!idleReturnDelegate.recordOrdinaryReturnCalled)
        #expect(idleReturnDelegate.showNewTabPageAfterIdleReturnCalled)
    }

    @Test(
        "Fire App Launched From external pixel when scheme is http or https",
        arguments: [
            "http://www.example.com",
            "https://www.example.com",
        ]
    )
    func fireAppLaunchedFromExternalPixelWhenSchemeIsHttpOrHttps(_ path: String) throws {
        // GIVEN
        let url = try #require(URL(string: path))
        let action = LaunchAction.openURL(url)
        #expect(pixelKitMock.actualFireCalls.count == 0)

        // WHEN
        launchActionHandler.handleLaunchAction(action)

        // THEN
        #expect(pixelKitMock.actualFireCalls.count == 1)
        #expect(pixelKitMock.actualFireCalls.first?.pixel.name == Pixel.Event.appLaunchFromExternalLink.name)
    }

    @Test(
        "Fire App Launched From external pixel when scheme is http or https",
        arguments: [
            "ddgQuickLink://http://www.example.com",
            "ddgQuickLink:/https://www.example.com",
        ]
    )
    func fireAppLaunchedFromExternalPixelWhenSchemeIsDDGQuickLink(_ path: String) throws {
        // GIVEN
        let url = try #require(URL(string: path))
        let action = LaunchAction.openURL(url)
        #expect(pixelKitMock.actualFireCalls.count == 0)

        // WHEN
        launchActionHandler.handleLaunchAction(action)

        // THEN
        #expect(pixelKitMock.actualFireCalls.count == 1)
        #expect(pixelKitMock.actualFireCalls.first?.pixel.name == Pixel.Event.appLaunchFromShareExtension.name)
    }

    // MARK: - LaunchSourceManager Integration Tests

    @Test("LaunchSourceManager is set to URL when handling openURL action")
    func launchSourceManagerSetToURLWhenHandlingOpenURL() {
        let url = URL(string: "https://example.com")!
        let action = LaunchAction.openURL(url)
        
        #expect(launchSourceManager.source == .standard)
        #expect(launchSourceManager.setSourceCallCount == 0)
        
        launchActionHandler.handleLaunchAction(action)
        
        #expect(launchSourceManager.source == .URL)
        #expect(launchSourceManager.lastSetSource == .URL)
        #expect(launchSourceManager.setSourceCallCount == 1)
    }
    
    @Test("LaunchSourceManager is set to shortcut when handling shortcut item action")
    func launchSourceManagerSetToShortcutWhenHandlingShortcutItem() {
        let shortcutItem = UIApplicationShortcutItem(type: "TestType", localizedTitle: "Test")
        let action = LaunchAction.handleShortcutItem(shortcutItem)
        
        #expect(launchSourceManager.source == .standard)
        #expect(launchSourceManager.setSourceCallCount == 0)
        
        launchActionHandler.handleLaunchAction(action)
        
        #expect(launchSourceManager.source == .shortcut)
        #expect(launchSourceManager.lastSetSource == .shortcut)
        #expect(launchSourceManager.setSourceCallCount == 1)
    }
    
    @Test("LaunchSourceManager is set to standard when standard launch")
    func launchSourceManagerSetToStandardWhenShowingKeyboard() {
        let date = Date()
        let action = LaunchAction.standardLaunch(lastBackgroundDate: date, isFirstForeground: false)

        launchSourceManager.setSource(.URL)
        #expect(launchSourceManager.source == .URL)
        
        launchActionHandler.handleLaunchAction(action)
        
        #expect(launchSourceManager.source == .standard)
        #expect(launchSourceManager.lastSetSource == .standard)
        #expect(launchSourceManager.setSourceCallCount == 2)
    }
    
    @Test("LaunchSourceManager source is set before URL processing when shouldProcessDeepLink is false")
    func launchSourceManagerSourceSetBeforeURLProcessingWhenShouldProcessDeepLinkIsFalse() {
        let url = URL(string: "https://example.com")!
        let action = LaunchAction.openURL(url)
        
        urlHandler.shouldProcessDeepLinkResult = false
        
        launchActionHandler.handleLaunchAction(action)
        
        #expect(launchSourceManager.source == .URL)
        #expect(launchSourceManager.lastSetSource == .URL)
        #expect(launchSourceManager.setSourceCallCount == 1)
        #expect(!urlHandler.handleURLCalled)
    }
    
    @Test("LaunchSourceManager maintains source across multiple actions")
    func launchSourceManagerMaintainsSourceAcrossMultipleActions() {

        #expect(launchSourceManager.source == .standard)
        
        let urlAction = LaunchAction.openURL(URL(string: "https://example.com")!)
        launchActionHandler.handleLaunchAction(urlAction)
        #expect(launchSourceManager.source == .URL)
        #expect(launchSourceManager.setSourceCallCount == 1)
        
        let shortcutAction = LaunchAction.handleShortcutItem(UIApplicationShortcutItem(type: "TestType", localizedTitle: "Test"))
        launchActionHandler.handleLaunchAction(shortcutAction)
        #expect(launchSourceManager.source == .shortcut)
        #expect(launchSourceManager.setSourceCallCount == 2)
        
        let keyboardAction = LaunchAction.standardLaunch(lastBackgroundDate: Date(), isFirstForeground: false)
        launchActionHandler.handleLaunchAction(keyboardAction)
        #expect(launchSourceManager.source == .standard)
        #expect(launchSourceManager.setSourceCallCount == 3)
    }
    
    @Test("LaunchSourceManager integration with all LaunchAction types")
    func launchSourceManagerIntegrationWithAllLaunchActionTypes() {

        let testCases: [(LaunchAction, LaunchSource)] = [
            (.openURL(URL(string: "https://example.com")!), .URL),
            (.handleShortcutItem(UIApplicationShortcutItem(type: "TestType", localizedTitle: "Test")), .shortcut),
            (.standardLaunch(lastBackgroundDate: Date(), isFirstForeground: false), .standard)
        ]
        
        for (index, (action, expectedSource)) in testCases.enumerated() {
            launchActionHandler.handleLaunchAction(action)

            #expect(launchSourceManager.source == expectedSource, "Failed at index \(index) for action \(action)")
            #expect(launchSourceManager.lastSetSource == expectedSource, "Failed at index \(index) for action \(action)")
            #expect(launchSourceManager.setSourceCallCount == index + 1, "Failed at index \(index) for action \(action)")
        }
    }

    // MARK: - Idle return

    @available(iOS 16, *)
    @Test(
        "When idle return with NTP treatment then showNewTabPageAfterIdleReturn is called and keyboard is not",
        .timeLimit(.minutes(1)),
        arguments: [
            (false, true),
            (false, false),
            (true, false)
        ] as [(Bool, Bool)]
    )
    func whenIdleReturnNTPTreatmentThenIdleReturnHandlerIsCalled(flagOn: Bool, keptCurrentNewTabPage: Bool) {
        let date = Date()
        featureFlagger.enabledFeatureFlags = flagOn ? [.alwaysShowKeyboardOnNewTabPage] : []
        idleReturnEvaluator.didReturnAfterIdleResult = true
        idleReturnEvaluator.treatmentForIdleReturnResult = .ntp
        idleReturnDelegate.showNewTabPageAfterIdleReturnResult = keptCurrentNewTabPage
        idleReturnDelegate.showNewTabPageAfterIdleReturnCalled = false
        keyboardPresenter.showKeyboardOnLaunchCalled = false

        launchActionHandler.handleLaunchAction(.standardLaunch(lastBackgroundDate: date, isFirstForeground: false))

        #expect(idleReturnDelegate.showNewTabPageAfterIdleReturnCalled)
        #expect(!idleReturnDelegate.markLastUsedTabAsResumedAfterIdleCalled)
        #expect(!keyboardPresenter.showKeyboardOnLaunchCalled)
    }

    @available(iOS 16, *)
    @Test(
        "When idle return keeps the current NTP and the flag is on then keyboard presenter is called",
        .timeLimit(.minutes(1)),
        arguments: [false, true]
    )
    func whenIdleReturnKeepsCurrentNTPAndFlagIsOnThenKeyboardIsCalled(isFirstForeground: Bool) {
        let date = Date()
        featureFlagger.enabledFeatureFlags = [.alwaysShowKeyboardOnNewTabPage]
        idleReturnEvaluator.didReturnAfterIdleResult = true
        idleReturnEvaluator.treatmentForIdleReturnResult = .ntp
        idleReturnDelegate.showNewTabPageAfterIdleReturnResult = true

        launchActionHandler.handleLaunchAction(.standardLaunch(lastBackgroundDate: date, isFirstForeground: isFirstForeground))

        #expect(idleReturnDelegate.showNewTabPageAfterIdleReturnCalled)
        #expect(!idleReturnDelegate.markLastUsedTabAsResumedAfterIdleCalled)
        #expect(keyboardPresenter.showKeyboardOnLaunchCalled)
        #expect(keyboardPresenter.lastBackgroundDate == (isFirstForeground ? nil : date))
        #expect(keyboardPresenter.isAfterIdleReturn)
    }

    @available(iOS 16, *)
    @Test(
        "When idle return with LUT treatment then markLastUsedTabAsResumedAfterIdle is called and keyboard shows",
        .timeLimit(.minutes(1)),
        arguments: [false, true]
    )
    func whenIdleReturnLUTTreatmentThenLUTHandlerIsCalled(flagOn: Bool) {
        let date = Date()
        featureFlagger.enabledFeatureFlags = flagOn ? [.alwaysShowKeyboardOnNewTabPage] : []
        idleReturnEvaluator.didReturnAfterIdleResult = true
        idleReturnEvaluator.treatmentForIdleReturnResult = .lut
        idleReturnDelegate.markLastUsedTabAsResumedAfterIdleCalled = false
        idleReturnDelegate.showNewTabPageAfterIdleReturnCalled = false
        keyboardPresenter.showKeyboardOnLaunchCalled = false

        launchActionHandler.handleLaunchAction(.standardLaunch(lastBackgroundDate: date, isFirstForeground: false))

        #expect(idleReturnDelegate.markLastUsedTabAsResumedAfterIdleCalled)
        #expect(!idleReturnDelegate.showNewTabPageAfterIdleReturnCalled)
        #expect(keyboardPresenter.showKeyboardOnLaunchCalled)
        #expect(keyboardPresenter.lastBackgroundDate == date)
        #expect(keyboardPresenter.isAfterIdleReturn)
    }

    @available(iOS 16, *)
    @Test(
        "When no idle return then showKeyboardOnLaunch is called and neither delegate is called",
        .timeLimit(.minutes(1)),
        arguments: [false, true]
    )
    func whenNoIdleReturnThenKeyboardIsCalled(flagOn: Bool) {
        let date = Date()
        featureFlagger.enabledFeatureFlags = flagOn ? [.alwaysShowKeyboardOnNewTabPage] : []
        idleReturnEvaluator.didReturnAfterIdleResult = false
        idleReturnDelegate.showNewTabPageAfterIdleReturnCalled = false
        idleReturnDelegate.markLastUsedTabAsResumedAfterIdleCalled = false
        keyboardPresenter.showKeyboardOnLaunchCalled = false

        launchActionHandler.handleLaunchAction(.standardLaunch(lastBackgroundDate: date, isFirstForeground: false))

        #expect(!idleReturnDelegate.showNewTabPageAfterIdleReturnCalled)
        #expect(!idleReturnDelegate.markLastUsedTabAsResumedAfterIdleCalled)
        #expect(keyboardPresenter.showKeyboardOnLaunchCalled)
        #expect(keyboardPresenter.lastBackgroundDate == date)
        #expect(!keyboardPresenter.isAfterIdleReturn)
    }

    @available(iOS 16, *)
    @Test("When isFirstForeground is true then keyboard presenter receives nil so keyboard shows on cold start", .timeLimit(.minutes(1)))
    func whenFirstForegroundThenKeyboardReceivesNil() {
        let date = Date()
        idleReturnEvaluator.didReturnAfterIdleResult = false
        keyboardPresenter.showKeyboardOnLaunchCalled = false

        launchActionHandler.handleLaunchAction(.standardLaunch(lastBackgroundDate: date, isFirstForeground: true))

        #expect(keyboardPresenter.showKeyboardOnLaunchCalled)
        #expect(keyboardPresenter.lastBackgroundDate == nil)
    }

}

struct NewTabPageKeyboardPolicyTests {

    struct AppOpenCase: Sendable {
        let onNewTab: Bool
        let onAppLaunch: Bool
        let onNewTabPage: Bool
        let showsKeyboard: Bool
    }

    @available(iOS 16, macOS 13, *)
    @Test(
        "App open follows New Tab on a New Tab Page, and App Launch elsewhere",
        .timeLimit(.minutes(1)),
        arguments: [
            AppOpenCase(onNewTab: true, onAppLaunch: false, onNewTabPage: true, showsKeyboard: true),
            AppOpenCase(onNewTab: true, onAppLaunch: true, onNewTabPage: true, showsKeyboard: true),
            AppOpenCase(onNewTab: false, onAppLaunch: true, onNewTabPage: true, showsKeyboard: false),
            AppOpenCase(onNewTab: false, onAppLaunch: false, onNewTabPage: true, showsKeyboard: false),
            AppOpenCase(onNewTab: true, onAppLaunch: false, onNewTabPage: false, showsKeyboard: false),
            AppOpenCase(onNewTab: true, onAppLaunch: true, onNewTabPage: false, showsKeyboard: true),
            AppOpenCase(onNewTab: false, onAppLaunch: true, onNewTabPage: false, showsKeyboard: true),
            AppOpenCase(onNewTab: false, onAppLaunch: false, onNewTabPage: false, showsKeyboard: false)
        ]
    )
    func whenAppOpensThenKeyboardFollowsTheSettingsTable(_ testCase: AppOpenCase) {
        let policy = NewTabPageKeyboardPolicy(onNewTab: testCase.onNewTab, onAppLaunch: testCase.onAppLaunch)

        #expect(policy.showsKeyboardOnAppOpen(onNewTabPage: testCase.onNewTabPage) == testCase.showsKeyboard)
    }

    @available(iOS 16, macOS 13, *)
    @Test(
        "App open is a cold start or a return after more than 20 seconds in the background",
        .timeLimit(.minutes(1)),
        arguments: [
            (nil, true),
            (21, true),
            (20, false),
            (5, false)
        ] as [(TimeInterval?, Bool)]
    )
    func whenReturningAfterTimeInBackgroundThenItIsAnAppOpenOnlyPastTheThreshold(secondsInBackground: TimeInterval?, isAppOpen: Bool) {
        let now = Date()
        let lastBackgroundDate = secondsInBackground.map { now.addingTimeInterval(-$0) }

        #expect(NewTabPageKeyboardPolicy.isAppOpen(lastBackgroundDate: lastBackgroundDate, now: now) == isAppOpen)
    }

    struct AfterFireCase: Sendable {
        let onNewTab: Bool
        let onDuckAITab: Bool
        let stillOnboarding: Bool
        let showsKeyboard: Bool
    }

    @Test(
        "After Fire New Tab decides, except on a Duck.ai tab or during onboarding",
        arguments: [
            AfterFireCase(onNewTab: true, onDuckAITab: false, stillOnboarding: false, showsKeyboard: true),
            AfterFireCase(onNewTab: true, onDuckAITab: false, stillOnboarding: true, showsKeyboard: false),
            AfterFireCase(onNewTab: true, onDuckAITab: true, stillOnboarding: false, showsKeyboard: false),
            AfterFireCase(onNewTab: true, onDuckAITab: true, stillOnboarding: true, showsKeyboard: false),
            AfterFireCase(onNewTab: false, onDuckAITab: false, stillOnboarding: false, showsKeyboard: false),
            AfterFireCase(onNewTab: false, onDuckAITab: false, stillOnboarding: true, showsKeyboard: false),
            AfterFireCase(onNewTab: false, onDuckAITab: true, stillOnboarding: false, showsKeyboard: false),
            AfterFireCase(onNewTab: false, onDuckAITab: true, stillOnboarding: true, showsKeyboard: false)
        ],
        [false, true]
    )
    func whenFireLandsOnNewTabPageThenKeyboardFollowsTheAfterFireTable(_ testCase: AfterFireCase, onAppLaunch: Bool) {
        // App Launch plays no part after Fire, so every row must hold with it on and off.
        let policy = NewTabPageKeyboardPolicy(onNewTab: testCase.onNewTab, onAppLaunch: onAppLaunch)

        let showsKeyboard = policy.showsKeyboardAfterFire(
            onDuckAITab: testCase.onDuckAITab,
            stillOnboarding: testCase.stillOnboarding)

        #expect(showsKeyboard == testCase.showsKeyboard)
    }

}

@MainActor
private final class MockAppOpenKeyboardHandler: AppOpenKeyboardHandling {
    var isNewTabPageVisible = true
    var appOpenKeyboardRequestID = UUID()
    var dismissalCompletion: (() -> Void)?
    var closeScreensCallCount = 0
    var allowedKeyboardCallCount = 0
    var legacyKeyboardCallCount = 0

    func closeScreensOverNewTabPageForIdleReturn(completion: @escaping () -> Void) {
        closeScreensCallCount += 1
        dismissalCompletion = completion
    }

    func showKeyboardOnAppOpenIfAllowed() {
        allowedKeyboardCallCount += 1
    }

    func enterSearchOnAppOpen() {
        legacyKeyboardCallCount += 1
    }
}

@MainActor
final class KeyboardPresenterTests {
    private let target = MockAppOpenKeyboardHandler()
    private let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [])
    private let pixelFiring = PixelKitMock()
    private var onAppLaunch = false
    private var scheduledActions: [() -> Void] = []
    private var afterPromptActions: [() -> Void] = []
    private var promptPending = false
    private var promptRequestIsValid: (@MainActor () -> Bool)?
    private var promptCloseHandler: (@MainActor () -> Void)?
    private lazy var presenter = KeyboardPresenter(
        mainViewController: target,
        featureFlagger: featureFlagger,
        runOnceModalPromptCloses: { [unowned self] isValid, handler in
            guard promptPending else { return false }
            promptRequestIsValid = isValid
            promptCloseHandler = handler
            return true
        },
        pixelFiring: pixelFiring,
        onAppLaunch: { [unowned self] in onAppLaunch },
        scheduleAfterPrompt: { [unowned self] in afterPromptActions.append($0) },
        schedule: { [unowned self] in scheduledActions.append($0) })

    @available(iOS 16, macOS 13, *)
    @Test("Cold launch preserves each flag path and the App Launch pixel condition", .timeLimit(.minutes(1)), arguments: [false, true], [false, true])
    func coldLaunch(flagOn: Bool, launchSetting: Bool) {
        featureFlagger.enabledFeatureFlags = flagOn ? [.alwaysShowKeyboardOnNewTabPage] : []
        onAppLaunch = launchSetting

        presenter.showKeyboardOnLaunch(lastBackgroundDate: nil, isAfterIdleReturn: false)

        #expect(target.closeScreensCallCount == 0)
        #expect(scheduledActions.count == (flagOn || launchSetting ? 1 : 0))
        #expect(pixelFiring.actualFireCalls.count == (launchSetting ? 1 : 0))
        if launchSetting {
            #expect(pixelFiring.actualFireCalls.first?.pixel.name == Pixel.Event.keyboardOnAppLaunchUsedDaily.name)
            #expect(pixelFiring.actualFireCalls.first?.frequency == .dailyAndCount)
        }
        #expect(target.allowedKeyboardCallCount == 0)
        #expect(target.legacyKeyboardCallCount == 0)

        scheduledActions.forEach { $0() }

        #expect(target.allowedKeyboardCallCount == (flagOn ? 1 : 0))
        #expect(target.legacyKeyboardCallCount == (!flagOn && launchSetting ? 1 : 0))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Both flag paths keep the 20-second background threshold", .timeLimit(.minutes(1)), arguments: [false, true], [5.0, 25.0])
    func backgroundThreshold(flagOn: Bool, secondsInBackground: TimeInterval) {
        featureFlagger.enabledFeatureFlags = flagOn ? [.alwaysShowKeyboardOnNewTabPage] : []
        onAppLaunch = true

        presenter.showKeyboardOnLaunch(lastBackgroundDate: Date().addingTimeInterval(-secondsInBackground), isAfterIdleReturn: false)

        #expect(scheduledActions.count == (secondsInBackground == 25 ? 1 : 0))
        #expect(pixelFiring.actualFireCalls.count == (secondsInBackground == 25 ? 1 : 0))
    }

    @available(iOS 16, macOS 13, *)
    @Test("An idle return waits for dismissal but never bypasses the keyboard threshold", .timeLimit(.minutes(1)), arguments: [false, true])
    func idleReturnWaitsForDismissal(isAppOpen: Bool) {
        featureFlagger.enabledFeatureFlags = [.alwaysShowKeyboardOnNewTabPage]
        let lastBackgroundDate = isAppOpen ? nil : Date().addingTimeInterval(-1)

        presenter.showKeyboardOnLaunch(lastBackgroundDate: lastBackgroundDate, isAfterIdleReturn: true)

        #expect(target.closeScreensCallCount == 1)
        #expect(scheduledActions.isEmpty)
        #expect(target.allowedKeyboardCallCount == 0)

        target.dismissalCompletion?()

        #expect(scheduledActions.count == (isAppOpen ? 1 : 0))
        scheduledActions.forEach { $0() }
        #expect(target.allowedKeyboardCallCount == (isAppOpen ? 1 : 0))
        #expect(pixelFiring.actualFireCalls.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A cancelled request or disabled flag cannot focus after dismissal or delay", .timeLimit(.minutes(1)), arguments: [false, true], [false, true])
    func invalidatedRequest(beforeDismissal: Bool, disableFlag: Bool) {
        featureFlagger.enabledFeatureFlags = [.alwaysShowKeyboardOnNewTabPage]
        presenter.showKeyboardOnLaunch(lastBackgroundDate: nil, isAfterIdleReturn: true)
        if !beforeDismissal {
            target.dismissalCompletion?()
            #expect(scheduledActions.count == 1)
        }

        if disableFlag {
            featureFlagger.enabledFeatureFlags = []
        } else {
            target.appOpenKeyboardRequestID = UUID()
        }
        if beforeDismissal {
            target.dismissalCompletion?()
            #expect(scheduledActions.isEmpty)
        }
        scheduledActions.forEach { $0() }

        #expect(target.allowedKeyboardCallCount == 0)
        #expect(target.legacyKeyboardCallCount == 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Flag-off requests retain legacy scheduling and ignore the cancellation token", .timeLimit(.minutes(1)))
    func flagOffPreservesLegacyCallback() {
        featureFlagger.enabledFeatureFlags = []
        onAppLaunch = true
        presenter.showKeyboardOnLaunch(lastBackgroundDate: nil, isAfterIdleReturn: true)
        target.appOpenKeyboardRequestID = UUID()
        featureFlagger.enabledFeatureFlags = [.alwaysShowKeyboardOnNewTabPage]

        scheduledActions.forEach { $0() }

        #expect(target.closeScreensCallCount == 0)
        #expect(target.legacyKeyboardCallCount == 1)
        #expect(target.allowedKeyboardCallCount == 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Idle-return cleanup only runs for a New Tab Page", .timeLimit(.minutes(1)))
    func otherTabsDoNotDismissScreens() {
        featureFlagger.enabledFeatureFlags = [.alwaysShowKeyboardOnNewTabPage]
        target.isNewTabPageVisible = false

        presenter.showKeyboardOnLaunch(lastBackgroundDate: nil, isAfterIdleReturn: true)

        #expect(target.closeScreensCallCount == 0)
        #expect(scheduledActions.count == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A pending prompt defers the keyboard until its close delay completes", .timeLimit(.minutes(1)))
    func promptDefersKeyboard() {
        featureFlagger.enabledFeatureFlags = [.alwaysShowKeyboardOnNewTabPage]
        promptPending = true
        presenter.showKeyboardOnLaunch()
        scheduledActions.forEach { $0() }
        #expect(target.allowedKeyboardCallCount == 0)
        #expect(promptRequestIsValid?() == true)

        promptCloseHandler?()
        #expect(afterPromptActions.count == 1)
        #expect(target.allowedKeyboardCallCount == 0)
        afterPromptActions.forEach { $0() }
        #expect(target.allowedKeyboardCallCount == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Invalidating a request stops waiting and focus after a prompt", .timeLimit(.minutes(1)), arguments: [false, true], [false, true])
    func invalidatedPromptRequest(afterClose: Bool, disableFlag: Bool) {
        featureFlagger.enabledFeatureFlags = [.alwaysShowKeyboardOnNewTabPage]
        promptPending = true
        presenter.showKeyboardOnLaunch()
        scheduledActions.forEach { $0() }
        if afterClose {
            promptCloseHandler?()
            #expect(afterPromptActions.count == 1)
        }

        if disableFlag {
            featureFlagger.enabledFeatureFlags = []
        } else {
            target.appOpenKeyboardRequestID = UUID()
        }
        #expect(promptRequestIsValid?() == false)
        if !afterClose {
            promptCloseHandler?()
            #expect(afterPromptActions.isEmpty)
        }
        afterPromptActions.forEach { $0() }
        #expect(target.allowedKeyboardCallCount == 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Flag-off launch never subscribes to prompt closure", .timeLimit(.minutes(1)))
    func flagOffDoesNotWaitForPrompt() {
        featureFlagger.enabledFeatureFlags = []
        promptPending = true
        onAppLaunch = true
        presenter.showKeyboardOnLaunch()
        scheduledActions.forEach { $0() }
        #expect(promptCloseHandler == nil)
        #expect(target.legacyKeyboardCallCount == 1)
    }

}
