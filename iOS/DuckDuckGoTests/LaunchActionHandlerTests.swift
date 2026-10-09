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
    var showKeyboardOnNewTabPageCreatedCallCount = 0
    var lastBackgroundDate: Date?
    var isAfterIdleReturn = false
    var hasCompletedAuthentication = true

    func showKeyboardOnLaunch(lastBackgroundDate: Date?, hasCompletedAuthentication: Bool, isAfterIdleReturn: Bool) {
        showKeyboardOnLaunchCalled = true
        self.lastBackgroundDate = lastBackgroundDate
        self.hasCompletedAuthentication = hasCompletedAuthentication
        self.isAfterIdleReturn = isAfterIdleReturn
    }

    func showKeyboardOnNewTabPageCreated() {
        showKeyboardOnNewTabPageCreatedCallCount += 1
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
    var showNewTabPageAfterIdleReturnResult: IdleReturnNewTabPageResult = .suppressed
    var completesNewTabPageImmediately = true
    var newTabPageCompletion: ((IdleReturnNewTabPageResult) -> Void)?
    var markLastUsedTabAsResumedAfterIdleCalled = false
    var recordOrdinaryReturnCalled = false

    func recordOrdinaryReturn(timeAwayMs: Int?) {
        recordOrdinaryReturnCalled = true
    }

    func showNewTabPageAfterIdleReturn(timeAwayMs: Int?, completion: @escaping (IdleReturnNewTabPageResult) -> Void) {
        showNewTabPageAfterIdleReturnCalled = true
        if completesNewTabPageImmediately {
            completion(showNewTabPageAfterIdleReturnResult)
        } else {
            newTabPageCompletion = completion
        }
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

    @available(iOS 16, macOS 13, *)
    @Test("A standard launch passes the authentication state to the keyboard", .timeLimit(.minutes(1)), arguments: [false, true])
    func passesAuthenticationStateToKeyboard(hasCompletedAuthentication: Bool) {
        let action = LaunchAction(actionToHandle: nil,
                                  lastBackgroundDate: Date(),
                                  isFirstForeground: false,
                                  hasCompletedAuthentication: hasCompletedAuthentication)

        launchActionHandler.handleLaunchAction(action)

        #expect(keyboardPresenter.showKeyboardOnLaunchCalled)
        #expect(keyboardPresenter.hasCompletedAuthentication == hasCompletedAuthentication)
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

    @available(iOS 16, macOS 13, *)
    @Test(
        "Flag-off or suppressed idle New Tab Page results do not request keyboard focus",
        .timeLimit(.minutes(1)),
        arguments: [
            (false, .keptCurrent),
            (false, .openedNewTab),
            (false, .suppressed),
            (true, .suppressed)
        ] as [(Bool, IdleReturnNewTabPageResult)]
    )
    func whenIdleReturnNTPTreatmentThenIdleReturnHandlerIsCalled(flagOn: Bool, result: IdleReturnNewTabPageResult) {
        let date = Date()
        featureFlagger.enabledFeatureFlags = flagOn ? [.alwaysShowKeyboardOnNewTabPage] : []
        idleReturnEvaluator.didReturnAfterIdleResult = true
        idleReturnEvaluator.treatmentForIdleReturnResult = .ntp
        idleReturnDelegate.showNewTabPageAfterIdleReturnResult = result
        idleReturnDelegate.showNewTabPageAfterIdleReturnCalled = false
        keyboardPresenter.showKeyboardOnLaunchCalled = false

        launchActionHandler.handleLaunchAction(.standardLaunch(lastBackgroundDate: date, isFirstForeground: false))

        #expect(idleReturnDelegate.showNewTabPageAfterIdleReturnCalled)
        #expect(!idleReturnDelegate.markLastUsedTabAsResumedAfterIdleCalled)
        #expect(!keyboardPresenter.showKeyboardOnLaunchCalled)
        #expect(keyboardPresenter.showKeyboardOnNewTabPageCreatedCallCount == 0)
    }

    @available(iOS 16, macOS 13, *)
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
        idleReturnDelegate.showNewTabPageAfterIdleReturnResult = .keptCurrent

        launchActionHandler.handleLaunchAction(.standardLaunch(lastBackgroundDate: date,
                                                               isFirstForeground: isFirstForeground,
                                                               hasCompletedAuthentication: false))

        #expect(idleReturnDelegate.showNewTabPageAfterIdleReturnCalled)
        #expect(!idleReturnDelegate.markLastUsedTabAsResumedAfterIdleCalled)
        #expect(keyboardPresenter.showKeyboardOnLaunchCalled)
        #expect(keyboardPresenter.lastBackgroundDate == (isFirstForeground ? nil : date))
        #expect(!keyboardPresenter.hasCompletedAuthentication)
        #expect(keyboardPresenter.isAfterIdleReturn)
        #expect(keyboardPresenter.showKeyboardOnNewTabPageCreatedCallCount == 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test("An inactivity-created New Tab Page requests focus only after creation, including short returns", .timeLimit(.minutes(1)))
    func createdNewTabPageWaitsForCompletion() throws {
        featureFlagger.enabledFeatureFlags = [.alwaysShowKeyboardOnNewTabPage]
        idleReturnEvaluator.didReturnAfterIdleResult = true
        idleReturnEvaluator.treatmentForIdleReturnResult = .ntp
        idleReturnDelegate.completesNewTabPageImmediately = false

        launchActionHandler.handleLaunchAction(.standardLaunch(lastBackgroundDate: Date().addingTimeInterval(-5), isFirstForeground: false))

        #expect(idleReturnDelegate.showNewTabPageAfterIdleReturnCalled)
        #expect(!keyboardPresenter.showKeyboardOnLaunchCalled)
        #expect(keyboardPresenter.showKeyboardOnNewTabPageCreatedCallCount == 0)

        let completion = try #require(idleReturnDelegate.newTabPageCompletion)
        completion(.openedNewTab)

        #expect(!keyboardPresenter.showKeyboardOnLaunchCalled)
        #expect(keyboardPresenter.showKeyboardOnNewTabPageCreatedCallCount == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Changing the flag while an idle New Tab Page is prepared does not request focus", .timeLimit(.minutes(1)),
          arguments: [false, true], [IdleReturnNewTabPageResult.keptCurrent, .openedNewTab])
    func changingFlagBeforeIdleCompletionDoesNotFocus(flagInitiallyOn: Bool, result: IdleReturnNewTabPageResult) throws {
        featureFlagger.enabledFeatureFlags = flagInitiallyOn ? [.alwaysShowKeyboardOnNewTabPage] : []
        idleReturnEvaluator.didReturnAfterIdleResult = true
        idleReturnEvaluator.treatmentForIdleReturnResult = .ntp
        idleReturnDelegate.completesNewTabPageImmediately = false

        launchActionHandler.handleLaunchAction(.standardLaunch(lastBackgroundDate: nil, isFirstForeground: true))
        featureFlagger.enabledFeatureFlags = flagInitiallyOn ? [] : [.alwaysShowKeyboardOnNewTabPage]
        let completion = try #require(idleReturnDelegate.newTabPageCompletion)
        completion(result)

        #expect(!keyboardPresenter.showKeyboardOnLaunchCalled)
        #expect(keyboardPresenter.showKeyboardOnNewTabPageCreatedCallCount == 0)
    }

    @available(iOS 16, *)
    @Test(
        "When idle return with LUT treatment then markLastUsedTabAsResumedAfterIdle is called and keyboard shows",
        .timeLimit(.minutes(1))
    )
    func whenIdleReturnLUTTreatmentThenLUTHandlerIsCalled() {
        let date = Date()
        featureFlagger.enabledFeatureFlags = []
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
        .timeLimit(.minutes(1))
    )
    func whenNoIdleReturnThenKeyboardIsCalled() {
        let date = Date()
        featureFlagger.enabledFeatureFlags = []
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
