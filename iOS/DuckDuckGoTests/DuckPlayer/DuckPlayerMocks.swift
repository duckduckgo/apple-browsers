//
//  DuckPlayerMocks.swift
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

import XCTest
import WebKit
import ContentScopeScripts
import Combine
import BrowserServicesKit
import SwiftUI

@testable import DuckDuckGo
@testable import Core

class MockWKNavigationDelegate: NSObject, WKNavigationDelegate {
    var didFinishNavigation: ((WKWebView, WKNavigation?) -> Void)?
    var didFailNavigation: ((WKWebView, WKNavigation?, Error) -> Void)?
    var decidePolicyForNavigationAction: ((WKWebView, WKNavigationAction, @escaping (WKNavigationActionPolicy) -> Void) -> Void)?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        didFinishNavigation?(webView, navigation)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        didFailNavigation?(webView, navigation, error)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decidePolicyForNavigationAction?(webView, navigationAction, decisionHandler) ?? decisionHandler(.allow)
    }
}

class MockWebView: WKWebView {

    var lastLoadedRequest: URLRequest?
    var loadedRequests: [URLRequest] = []
    var loadCallCount = 0
    var evaluateJavaScriptCalled = false
    var reloadCalled = false

    var loadCompletionHandler: (() -> Void)?

    /// The current URL of the web view.
    private var _url: URL?
    override var url: URL? {
        return _url
    }

    /// Sets the current URL of the web view.
    func setCurrentURL(_ url: URL) {
        self._url = url
    }

    /// A simulated history stack to support navigation methods like `goBack()`.
    var historyStack: [URL] = []

    /// Indicates whether the `stopLoading()` method was called.
    var didStopLoadingCalled = false

    // MARK: - Overridden Methods

    override func load(_ request: URLRequest) -> WKNavigation? {
        lastLoadedRequest = request
        loadedRequests.append(request)
        loadCallCount += 1

        // Simulate asynchronous loading
        DispatchQueue.main.async {
            self.loadCompletionHandler?()
        }

        return nil
    }

    override func reload() -> WKNavigation? {
        reloadCalled = true
        // Simulate reload behavior if needed
        return nil
    }

    override func goBack() -> WKNavigation? {
        if historyStack.count > 1 {
            // Remove the current page
            historyStack.removeLast()
            // Set the URL to the previous page
            setCurrentURL(historyStack.last!)
        }
        return nil
    }

    override func stopLoading() {
        didStopLoadingCalled = true
    }

    // MARK: - Additional Helper Methods (if needed)

    /// Simulates navigating to a new URL.
    func navigate(to url: URL) {
        historyStack.append(url)
        setCurrentURL(url)
    }

    /// Resets the web view's state.
    func reset() {
        lastLoadedRequest = nil
        loadedRequests.removeAll()
        loadCallCount = 0
        didStopLoadingCalled = false
        historyStack.removeAll()
        _url = nil
        loadCompletionHandler = nil
    }
}

class MockNavigationAction: WKNavigationAction {
    private let _request: URLRequest
    private let _navigationType: WKNavigationType
    private let _targetFrame: WKFrameInfo?
    var isTargetingMainFrameResult = true

    init(request: URLRequest, navigationType: WKNavigationType = .linkActivated, targetFrame: WKFrameInfo? = nil) {
        self._request = request
        self._navigationType = navigationType
        self._targetFrame = targetFrame
    }

    override var request: URLRequest {
        return _request
    }

    override var navigationType: WKNavigationType {
        return _navigationType
    }

    override var targetFrame: WKFrameInfo? {
        return _targetFrame
    }
}

class MockFrameInfo: WKFrameInfo {
    private let _isMainFrame: Bool

    init(isMainFrame: Bool) {
        self._isMainFrame = isMainFrame
    }

    override var isMainFrame: Bool {
        return _isMainFrame
    }
}

final class MockDuckPlayerSettings: DuckPlayerSettings {

    private let duckPlayerSettingsSubject = PassthroughSubject<Void, Never>()
    var duckPlayerSettingsPublisher: AnyPublisher<Void, Never> {
        duckPlayerSettingsSubject.eraseToAnyPublisher()
    }

    var mode: DuckPlayerMode = .disabled
    var askModeOverlayHidden: Bool = false
    var allowFirstVideo: Bool = false
    var openInNewTab: Bool = false
    var nativeUI: Bool = false
    var autoplay: Bool = false
    var customError: Bool = false
    var customErrorSettings: DuckDuckGo.CustomErrorSettings? = CustomErrorSettings(signInRequiredSelector: "")
    var nativeUISERPEnabled: Bool = true
    var nativeUIYoutubeMode: DuckDuckGo.NativeDuckPlayerYoutubeMode = .allCases.first!
    var nativeUIPrimingModalPresentedCount: Int = 0
    var duckPlayerNativeUIPrimingModalTimeSinceLastPresented: Int = 0
    var variant: DuckDuckGo.DuckPlayerVariant = .classicWeb

    init(appSettings: any DuckDuckGo.AppSettings, privacyConfigManager: any BrowserServicesKit.PrivacyConfigurationManaging, internalUserDecider: any BrowserServicesKit.InternalUserDecider) {}

    func triggerNotification() {}

    func setMode(_ mode: DuckPlayerMode) {
        self.mode = mode
    }

    func setAskModeOverlayHidden(_ overlayHidden: Bool) {
        self.askModeOverlayHidden = overlayHidden
    }

}

final class MockDuckPlayerHosting: UIViewController, DuckPlayerHosting {
    var chromeVisible: Bool = false
    var chromeHidden: Bool = false

    var url: URL?
    var delegate: (any DuckDuckGo.TabDelegate)?
    var webView: WKWebView!
    var contentBottomConstraint: NSLayoutConstraint?
    var persistentBottomBarHeight: CGFloat = 0
    var presentCalled = false
    private var _presentedVC: UIViewController?

    override var presentedViewController: UIViewController? {
        get { return _presentedVC }
    }

    override func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
        _presentedVC = viewControllerToPresent
        presentCalled = true
        super.present(viewControllerToPresent, animated: flag, completion: completion)
    }

    override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        _presentedVC = nil
        super.dismiss(animated: flag, completion: completion)
    }

    func showChrome() {
        chromeVisible = true
    }

    func hideChrome() {
        chromeVisible = false
    }

    func setupWebViewForPortraitVideo() {
        // NOOP
    }

    func setupWebViewForLandscapeVideo() {
        // NOOP
    }

    func isTabCurrentlyPresented() -> Bool {
        return true
    }

}

final class MockDuckPlayer: DuckPlayerControlling {

    // MARK: - Required Properties
    var settings: DuckPlayerSettings
    var hostView: DuckPlayerHosting?
    var youtubeNavigationRequest: PassthroughSubject<URL, Never>
    var playerDismissedPublisher: PassthroughSubject<Void, Never>

    // MARK: - Testing Properties
    var presentPillCalled = false
    var dismissPillCalled = false
    var loadNativeDuckPlayerVideoCalled = false
    var lastPresentedVideoID: String?
    var lastDismissPillReset = false
    var lastDismissPillAnimated = false
    var lastDismissPillProgramatic = false

    // MARK: - Private Properties
    private var featureFlagger: FeatureFlagger
    private var nativeUIPresenter: DuckPlayerNativeUIPresenting

    // MARK: - Initialization
    init(settings: DuckPlayerSettings, featureFlagger: FeatureFlagger, nativeUIPresenter: DuckPlayerNativeUIPresenting = MockDuckPlayerNativeUIPresenting(), featureDiscovery: FeatureDiscovery = MockFeatureDiscovery()) {
        self.settings = settings
        self.featureFlagger = featureFlagger
        self.nativeUIPresenter = nativeUIPresenter
        self.youtubeNavigationRequest = PassthroughSubject<URL, Never>()
        self.playerDismissedPublisher = PassthroughSubject<Void, Never>()
    }

    // MARK: - User Values Methods
    func setUserValues(params: Any, message: WKScriptMessage) -> (any Encodable)? {
        nil
    }

    func getUserValues(params: Any, message: WKScriptMessage) -> (any Encodable)? {
        nil
    }

    // MARK: - Video Handling Methods
    @MainActor
    func openVideoInDuckPlayer(url: URL, webView: WKWebView) {
        // Mock implementation
    }

    func loadNativeDuckPlayerVideo(videoID: String, source: DuckPlayer.VideoNavigationSource, timestamp: TimeInterval?) {
        loadNativeDuckPlayerVideoCalled = true
        // Mock implementation
    }

    // MARK: - Setup Methods
    func initialSetupPlayer(params: Any, message: WKScriptMessage) async -> (any Encodable)? {
        nil
    }

    func initialSetupOverlay(params: Any, message: WKScriptMessage) async -> (any Encodable)? {
        nil
    }

    func setHostViewController(_ vc: any DuckDuckGo.DuckPlayerHosting) {
        self.hostView = vc
    }

    // MARK: - Settings Methods
    func openDuckPlayerSettings() {
        // Mock implementation
    }

    func openDuckPlayerSettings(params: Any, message: WKScriptMessage) async -> (any Encodable)? {
        nil
    }

    func openDuckPlayerInfo(params: Any, message: WKScriptMessage) async -> (any Encodable)? {
        nil
    }

    // MARK: - Error Handling
    func handleYoutubeError(params: Any, message: WKScriptMessage) async -> (any Encodable)? {
        nil
    }

    // MARK: - Telemetry
    func telemetryEvent(params: Any, message: WKScriptMessage) async -> (any Encodable)? {
        nil
    }

    // MARK: - Pill UI Methods
    func presentPill(for videoID: String, timestamp: TimeInterval?) {
        presentPillCalled = true
        lastPresentedVideoID = videoID
    }

    func dismissPill(reset: Bool, animated: Bool, programatic: Bool) {
        dismissPillCalled = true
        lastDismissPillReset = reset
        lastDismissPillAnimated = animated
        lastDismissPillProgramatic = programatic
    }

    func hidePillForHiddenChrome() {
        // Mock implementation
    }

    func showPillForVisibleChrome() {
        // Mock implementation
    }

}

enum MockFeatureFlag: Hashable {
    case duckPlayer, duckPlayerOpenInNewTab
}

final class MockDuckPlayerFeatureFlagger: FeatureFlagger {
    var internalUserDecider: InternalUserDecider = DefaultInternalUserDecider(store: MockInternalUserStoring())
    var localOverrides: FeatureFlagLocalOverriding?

    var enabledFeatures: Set<MockFeatureFlag> = []

    func isFeatureOn(_ feature: MockFeatureFlag) -> Bool {
        return enabledFeatures.contains(feature)
    }

    func isFeatureOn<Flag: FeatureFlagDescribing>(for featureFlag: Flag, allowOverride: Bool) -> Bool {
        return !enabledFeatures.isEmpty
    }

    func getCohortIfEnabled(_ subfeature: any PrivacySubfeature) -> CohortID? {
        return nil
    }

    func resolveCohort<Flag>(for featureFlag: Flag, allowOverride: Bool) -> (any FeatureFlagCohortDescribing)? where Flag: FeatureFlagDescribing {
        return nil
    }

    var allActiveExperiments: Experiments = [:]
}

final class MockDuckPlayerStorage: DuckPlayerStorage {
    var userInteractedWithDuckPlayer: Bool = false
}

final class MockDuckPlayerTabNavigator: DuckPlayerTabNavigationHandling {
    var openedURL: URL?
    var closeTabCalled = false

    func openTab(for url: URL) {
        openedURL = url
    }

    func closeTab() {
        closeTabCalled = true
    }
}

final class MockDuckPlayerInternalUserDecider: InternalUserDecider {
    var mockIsInternalUser: Bool = false
    var mockIsInternalUserPublisher: AnyPublisher<Bool, Never> {
        Just(mockIsInternalUser).eraseToAnyPublisher()
    }

    var isInternalUser: Bool {
        return mockIsInternalUser
    }

    var isInternalUserPublisher: AnyPublisher<Bool, Never> {
        return mockIsInternalUserPublisher
    }

    @discardableResult
    func markUserAsInternalIfNeeded(forUrl url: URL?, response: HTTPURLResponse?) -> Bool {
        return mockIsInternalUser
    }
}

final class MockDuckPlayerNativeUIPresenting: DuckPlayerNativeUIPresenting {

    var presentPillCalled = false
    var dismissPillCalled = false
    var presentDuckPlayerCalled = false
    var lastTimestampValue: TimeInterval?

    @MainActor
    func presentPill(for videoID: String, in hostViewController: any DuckDuckGo.DuckPlayerHosting, timestamp: TimeInterval?) {
        presentPillCalled = true
        lastTimestampValue = timestamp
    }

    @MainActor
    func dismissPill(reset: Bool, animated: Bool, programatic: Bool) {}

    @MainActor
    func presentDuckPlayer(videoID: String, source: DuckDuckGo.DuckPlayer.VideoNavigationSource, in hostViewController: any DuckDuckGo.DuckPlayerHosting, title: String?, timestamp: TimeInterval?) -> (navigation: PassthroughSubject<URL, Never>, settings: PassthroughSubject<Void, Never>) {
        presentDuckPlayerCalled = true
        return (PassthroughSubject<URL, Never>(), PassthroughSubject<Void, Never>())
    }

    var videoPlaybackRequest: PassthroughSubject<(videoID: String, timestamp: TimeInterval?), Never>

    init() {
        self.videoPlaybackRequest = PassthroughSubject<(videoID: String, timestamp: TimeInterval?), Never>()
    }

    @MainActor
    func showBottomSheetForVisibleChrome() {}

    @MainActor
    func hideBottomSheetForHiddenChrome() {}
}

class MockDelayHandler: DuckPlayerDelayHandling {
    private var delaySubject = PassthroughSubject<Void, Never>()
    private var delayCancellable: AnyCancellable?

    func delay(seconds: TimeInterval) -> AnyPublisher<Void, Never> {
        delaySubject.eraseToAnyPublisher()
    }

    func completeDelay() {
        delaySubject.send()
    }
}

// MARK: - TabViewController Test Protocol

// MARK: - DuckPlayerTabViewControllerMock

final class DuckPlayerTabViewControllerMock: UIViewController {

    var webViewContainerView: UIView = UIView()
    var chromeDelegate: DuckPlayerBrowserChromeDelegateMock?
    var webViewBottomAnchorConstraint: NSLayoutConstraint?

    // Track presentation state
    private(set) var presentCalled = false
    private(set) var dismissCalled = false
    private(set) var lastPresentedViewController: UIViewController?
    private(set) var lastPresentedAnimated: Bool?
    private(set) var lastPresentedCompletion: (() -> Void)?

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        webViewBottomAnchorConstraint = NSLayoutConstraint()
        webViewBottomAnchorConstraint?.constant = 0
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func present(_ viewController: UIViewController, animated: Bool, completion: (() -> Void)?) {
        presentCalled = true
        lastPresentedViewController = viewController
        lastPresentedAnimated = animated
        lastPresentedCompletion = completion
        super.present(viewController, animated: animated, completion: completion)
    }

    override func dismiss(animated: Bool, completion: (() -> Void)?) {
        dismissCalled = true
        super.dismiss(animated: animated, completion: completion)
    }

    func setupWebViewForPortraitVideo() {
        // Implementation not needed for tests
    }

    func setupWebViewForLandscapeVideo() {
        // Implementation not needed for tests
    }
}

// Add MockNotificationCenter
final class MockNotificationCenter {
    var postCalled = false
    var lastPostedNotification: Notification?

    func post(name: Notification.Name, object: Any?, userInfo: [AnyHashable: Any]?) {
        postCalled = true
        lastPostedNotification = Notification(name: name, object: object, userInfo: userInfo)
    }
}

// MARK: - DuckPlayerChromeDelegateMock

final class DuckPlayerBrowserChromeDelegateMock: BrowserChromeDelegate {
    func setBarsHidden(_ hidden: Bool, animated: Bool, customAnimationDuration: CGFloat?) {
        setBarsHidden(hidden, animated: animated)
    }

    func setBarsVisibility(_ percent: CGFloat, animated: Bool, animationDuration: CGFloat?) {
        setBarsVisibility(percent, animated: animated)
    }

    enum Message: Equatable {
        case setBarsHidden(Bool)
        case setNavigationBarHidden(Bool)
        case setBarsVisibility(CGFloat)
        case setRefreshControlEnabled(Bool)
    }

    var receivedMessages: [Message] = []

    func setBarsHidden(_ hidden: Bool, animated: Bool) {
        receivedMessages.append(.setBarsHidden(hidden))
    }

    func setNavigationBarHidden(_ hidden: Bool) {
        receivedMessages.append(.setNavigationBarHidden(hidden))
    }

    func setBarsVisibility(_ percent: CGFloat, animated: Bool) {
        receivedMessages.append(.setBarsVisibility(percent))
    }

    func setRefreshControlEnabled(_ isEnabled: Bool) {
        receivedMessages.append(.setRefreshControlEnabled(isEnabled))
    }

    var canHideBars: Bool = false

    var isToolbarHidden: Bool = false

    var toolbarHeight: CGFloat = 0.0

    var barsMaxHeight: CGFloat = 30

    var omniBar: OmniBar = DefaultOmniBarViewController(
        dependencies: MockOmnibarDependency(
            voiceSearchHelper: MockVoiceSearchHelper(
                isSpeechRecognizerAvailable: true,
                voiceSearchEnabled: true
            )
        )
    )

    var tabBarContainer: UIView = UIView()
}
