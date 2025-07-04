//
//  NativeDuckPlayerNavigationHandler.swift
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

import Foundation
import ContentScopeScripts
import WebKit
import Core
import Common
import BrowserServicesKit
import DuckPlayer
import os.log
import Combine

/// Handles navigation and interactions related to Duck Player within the app.
final class NativeDuckPlayerNavigationHandler: NSObject {

    /// The DuckPlayer instance used for handling video playback.
    var duckPlayer: DuckPlayerControlling

    /// Indicates where the DuckPlayer was referred from (e.g., YouTube, SERP).
    var referrer: DuckPlayerReferrer = .other

    /// Feature flag manager for enabling/disabling features.
    var featureFlagger: FeatureFlagger

    /// Application settings.
    var appSettings: AppSettings

    /// Disable DuckPlayer for next video
    var disableDuckPlayerForNextVideo = false

    /// Delegate for handling tab navigation events.
    weak var tabNavigationHandler: DuckPlayerTabNavigationHandling?

    /// Cancellable for observing DuckPlayer Navigation Request
    @MainActor private var duckPlayerNavigationRequestCancellable: AnyCancellable?

    /// Cancellable for observing DuckPlayer settings
    @MainActor private var duckPlayerSettingsCancellable: AnyCancellable?

    /// Cancellable for observing DuckPlayer dismissal
    @MainActor private var duckPlayerDismissalCancellable: AnyCancellable?

    /// isLinkPreview is true when the DuckPlayer is opened from a link preview
    var isLinkPreview = false

    /// lastHandledVideoID is the last video ID that was handled by the DuckPlayer
    var lastHandledVideoID: String?

    /// DelayHandler for delaying actions
    private let delayHandler: DuckPlayerDelayHandling

    /// Cancellables for delaying actions
    private var cancellables = Set<AnyCancellable>()

    /// isDuckPlayerPresented is true when the DuckPlayer is presented
    private(set) var isDuckPlayerPillPresented = false
    private(set) var isDuckPlayerPresented = false

    private struct Constants {
        static let duckPlayerScheme = URL.NavigationalScheme.duck.rawValue
        static let serpNotifyEnabled = "enabled"
        static let serpNotifyDisabled = "disabled"
        static let pillPresentationDelay: TimeInterval = 1.0
        static let playerPresentationDelay: TimeInterval = 1.0
    }

    // ContentScopeScripts for Media Control is still in development
    // so we are using the default original implementation for now
    // and ijecting some JS to control youtube pausing
    private var useContentScopeScriptsForMediaControl = true

    /// JavaScript for media playback control
    private let mediaControlScript: String = {
        guard let url = Bundle.main.url(forResource: "mediaControl", withExtension: "js"),
              let script = try? String(contentsOf: url) else {
            assertionFailure("Failed to load mute audio script")
            return ""
        }
        return script
    }()

    /// Initializes a new instance of `DuckPlayerNavigationHandler` with the provided dependencies.
    ///
    /// - Parameters:
    ///   - duckPlayer: The DuckPlayer instance.
    ///   - featureFlagger: The feature flag manager.
    ///   - appSettings: The application settings.
    ///   - pixelFiring: The pixel firing utility for analytics.
    ///   - dailyPixelFiring: The daily pixel firing utility for analytics.
    ///   - tabNavigationHandler: The tab navigation handler delegate.
    init(duckPlayer: DuckPlayerControlling = DuckPlayer(),
         featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger,
         appSettings: AppSettings,
         tabNavigationHandler: DuckPlayerTabNavigationHandling? = nil,
         delayHandler: DuckPlayerDelayHandling = DuckPlayerDelayHandler()) {
        self.duckPlayer = duckPlayer
        self.featureFlagger = featureFlagger
        self.appSettings = appSettings
        self.tabNavigationHandler = tabNavigationHandler
        self.delayHandler = delayHandler
        super.init()
    }

    deinit {
        duckPlayerNavigationRequestCancellable?.cancel()
        duckPlayerSettingsCancellable?.cancel()
        duckPlayerDismissalCancellable?.cancel()
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
        NotificationCenter.default.removeObserver(self)
    }

    /// Sets the referrer based on the current web view 
    ///
    /// - Parameter webView: The `WKWebView` whose URL is used to determine the referrer.
    private func setReferrer(webView: WKWebView) {

        guard let url = webView.url else { return }

        // SERP as a referrer
        if url.isDuckDuckGoSearch {
            referrer = .serp
            return
        }

        // Any Other Youtube URL or other referrer
        if url.isYoutube {
            referrer = .youtube
            return
        } else {
            referrer = .other
        }
    }

    /// Loads a native DuckPlayerView
    /// - Parameter videoID: The ID of the video to load
    @MainActor
    private func loadNativeDuckPlayerVideo(videoID: String) {
        let source: DuckPlayer.VideoNavigationSource = switch referrer {
        case .youtube: .youtube
        case .serp: .serp
        case .other: .other
        default: .other
        }
        duckPlayer.loadNativeDuckPlayerVideo(videoID: videoID, source: source, timestamp: nil)
    }

    /// Toggles audio playback for a specific webView.
    ///
    /// - Parameters:
    ///  - webView: The `WKWebView` to manipulate.
    ///  - mute: Whether to mute the audio.
    @MainActor
    private func toggleAudioForTab(_ webView: WKWebView, mute: Bool) {
        if duckPlayer.settings.openInNewTab || duckPlayer.settings.nativeUI {
            duckPlayer.muteAudioPublisher.send(mute)
        }
    }

    /// Register a DuckPlayer Youtube Navigation Request observer
    /// Used when DuckPlayer requires direct Youtube Navigation
    @MainActor
    private func setupYoutubeNavigationRequestObserver(webView: WKWebView) {
        weak var weakWebView = webView
        duckPlayerNavigationRequestCancellable = duckPlayer.youtubeNavigationRequest
            .sink { [weak self] url in
                guard let self = self, let webView = weakWebView else { return }
                self.disableDuckPlayerForNextVideo = true
                let request = URLRequest(url: url)
                webView.load(request)
            }
    }

    /// Toggles pause and audio for all media elements in a webView.
    ///
    /// - Parameters:
    ///   - webView: The `WKWebView` to manipulate
    ///   - pause: When true, blocks media playback. When false, allows playback
    @MainActor
    private func toggleMediaPlayback(_ webView: WKWebView, pause: Bool) {
        if let url = webView.url, url.isYoutubeWatch {
            if useContentScopeScriptsForMediaControl {
                duckPlayer.mediaControlPublisher.send(pause)
            } else {
                webView.evaluateJavaScript("\(mediaControlScript); mediaControl(\(pause))")
            }
        }
    }

    // Temporarily pause media playback
    @MainActor
    private func pauseVideoStart(webView: WKWebView) async {
        if useContentScopeScriptsForMediaControl {
            duckPlayer.mediaControlPublisher.send(true)
        } else {
            await javascriptPauseVideoStart(webView: webView)
        }
    }

    // Temporarily pause media playback during page transition
    // The pause is applied repeatedly for 1 second to ensure it takes effect
    // even if the DOM is changing during early initialization
    // Once the page has loaded, the JS mutation observer takes care
    // Of pausing newly added elements.
    // This is a temporary solution until ContentScopeScripts for Media Control is ready
    @MainActor
    private func javascriptPauseVideoStart(webView: WKWebView) async {
        weak var weakWebView = webView
        Task { @MainActor [weak self] in
            let startTime = Date()
            while Date().timeIntervalSince(startTime) < 1.0 {
                guard let self = self, let webView = weakWebView else { break }
                self.toggleMediaPlayback(webView, pause: true)
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }

    /// Resets the DuckPlayer Presentation State
    private func resetDuckPlayerPresentation() {
        isDuckPlayerPillPresented = false
        isDuckPlayerPresented = false
    }

    // Notify UserScript of URL Change to pause media playback if needed
    private func notifyUserScriptOfURLChange(webView: WKWebView, newURL: URL?) {
        if let newURL = newURL {
            duckPlayer.urlChangedPublisher.send(newURL)
        }
    }

    /// Presents the DuckPlayer Pill with a delay   
    /// - Parameters:    
    ///   - videoID: The ID of the video to load
    ///   - timestamp: The timestamp of the video
    private func presentDuckPlayerPill(for videoID: String, timestamp: TimeInterval?) {
        isDuckPlayerPillPresented = true
        delayHandler.delay(seconds: Constants.pillPresentationDelay)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.duckPlayer.presentPill(for: videoID, timestamp: timestamp)
                }
            }
            .store(in: &cancellables)
    }

    /// Presents the DuckPlayer with a delay
    /// - Parameters:
    ///   - videoID: The ID of the video to load
    ///   - timestamp: The timestamp of the video
    private func presentDuckPlayer(for videoID: String, timestamp: TimeInterval?) {
        isDuckPlayerPresented = true
        delayHandler.delay(seconds: Constants.playerPresentationDelay)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.loadNativeDuckPlayerVideo(videoID: videoID)
                }
            }
            .store(in: &cancellables)
    }

    /// Dismisses the DuckPlayer Pill
    /// - Parameters:
    ///   - reset: Whether to reset the DuckPlayer state
    ///   - animated: Whether to animate the dismissal
    ///   - programatic: Whether the dismissal is programmatic
    private func dismissDuckPlayerPill(reset: Bool, animated: Bool, programatic: Bool) {
        isDuckPlayerPillPresented = false
        Task { @MainActor in
            duckPlayer.dismissPill(reset: reset, animated: animated, programatic: programatic, skipTransition: true)
        }
    }
}

extension NativeDuckPlayerNavigationHandler: DuckPlayerNavigationHandling {

    /// Manages navigation actions to Duck Player URLs, handling redirects and loading as needed.
    ///
    /// - Parameters:
    ///   - navigationAction: The `WKNavigationAction` to handle.
    ///   - webView: The `WKWebView` where navigation is occurring.
    @MainActor
    func handleDuckNavigation(_ navigationAction: WKNavigationAction, webView: WKWebView) {
        lastHandledVideoID = nil
        let (videoID, _) = navigationAction.request.url?.youtubeVideoParams ?? ("", nil)
        let youtubeURL = URL.youtube(videoID)
        webView.load(URLRequest(url: youtubeURL))
        _ = handleURLChange(webView: webView, previousURL: nil, newURL: youtubeURL)
        return
    }

    // swiftlint:disable cyclomatic_complexity
    /// Observes URL changes and redirects to Duck Player when appropriate, avoiding duplicate handling.
    ///
    /// - Parameter webView: The `WKWebView` whose URL has changed.
    /// - Returns: A result indicating whether the URL change was handled.
    @MainActor
    func handleURLChange(webView: WKWebView, previousURL: URL?, newURL: URL?) -> DuckPlayerNavigationHandlerURLChangeResult {

        guard featureFlagger.isFeatureOn(.duckPlayer) else { return .notHandled(.featureOff) }

        // Skip if the new URL is a YouTube watch page with a hashtag
        // This is a special case where YouTube navigates to/from intenal UI (Search, setttings, etc)
        if let previousID = previousURL?.youtubeVideoParams?.0,
           let newID = newURL?.youtubeVideoParams?.0,
           previousID == newID,
           newURL?.isYoutubeWatchWithHashtag == true || previousURL?.isYoutubeWatchWithHashtag == true {
            return .notHandled(.isYoutubeInternalNavigation)
        }

        // Reset the DuckPlayer Presentation State
        resetDuckPlayerPresentation()

        // If we are in link preview mode, we don't need to show the DuckPlayer Pill
        if isLinkPreview {
            return .notHandled(.isLinkPreview)
        }

        // Check if DuckPlayer feature is enabled
        guard featureFlagger.isFeatureOn(.duckPlayer) else {
            return .notHandled(.featureOff)
        }

        // Set the referrer
        setReferrer(webView: webView)

        // Dismiss the DuckPlayer Pill
        dismissDuckPlayerPill(reset: true, animated: true, programatic: true)

        // Never present DuckPlayer pill on DuckDuckGo search pages (SERP)
        guard let url = newURL, !url.isDuckDuckGoSearch else {
            lastHandledVideoID = nil
            return .notHandled(.invalidURL)
        }

        // Never present DuckPlayer for non-YouTube URLs
        guard let (videoID, _) = url.youtubeVideoParams else {
            lastHandledVideoID = nil
            return .notHandled(.invalidURL)
        }

        // Only present DuckPlayer for YouTube Watch URLs
        guard url.isYoutubeWatch else {
            lastHandledVideoID = nil
            return .notHandled(.isNotYoutubeWatch)
        }

        if disableDuckPlayerForNextVideo {
            disableDuckPlayerForNextVideo = false
            return .notHandled(.disabledForVideo)
        }

        // Get video ID from URL        
        guard videoID != lastHandledVideoID else {
            return .notHandled(.disabledForVideo)
        }

        // Ensure pill is dismissed if DuckPlayer is disabled
        if duckPlayer.settings.nativeUIYoutubeMode == .never {
            lastHandledVideoID = nil
            return .notHandled(.duckPlayerDisabled)
        }


        // Present Duck Player Pill (Native entry point)
        if duckPlayer.settings.nativeUIYoutubeMode == .ask {
            lastHandledVideoID = videoID
            notifyUserScriptOfURLChange(webView: webView, newURL: newURL)
            presentDuckPlayerPill(for: videoID, timestamp: nil)
            return .handled(.duckPlayerEnabled)
        }

        // Present Duck Player
        if duckPlayer.settings.nativeUIYoutubeMode == .auto {
            lastHandledVideoID = videoID
            notifyUserScriptOfURLChange(webView: webView, newURL: newURL)
            Task { @MainActor in await pauseVideoStart(webView: webView) }
            presentDuckPlayerPill(for: videoID, timestamp: nil)
            presentDuckPlayer(for: videoID, timestamp: nil)
            return .handled(.duckPlayerEnabled)
        }

        // Resume media playback
        toggleMediaPlayback(webView, pause: false)
        return .notHandled(.isNotYoutubeWatch)
    }
    // swiftlint:enable cyclomatic_complexity

    /// Custom back navigation logic to handle Duck Player in the web view's history stack.
    ///
    /// - Parameter webView: The `WKWebView` to navigate back in.
    @MainActor
    func handleGoBack(webView: WKWebView) {
        lastHandledVideoID = nil
    }

    /// Custom forward navigation logic to handle Duck Player in the web view's history stack.
    ///
    /// - Parameter webView: The `WKWebView` to navigate back in.
    @MainActor
    func handleGoForward(webView: WKWebView) {
        lastHandledVideoID = nil
    }

    /// Handles reload actions, ensuring Duck Player settings are respected during the reload.
    ///
    /// - Parameter webView: The `WKWebView` to reload.
    @MainActor
    func handleReload(webView: WKWebView) {
        webView.reload()

        guard featureFlagger.isFeatureOn(.duckPlayer) else { return }

        lastHandledVideoID = nil
        duckPlayer.dismissPill(reset: true, animated: false, programatic: true, skipTransition: true)
        _ = handleURLChange(webView: webView, previousURL: nil, newURL: webView.url)

    }

    /// Initializes settings and potentially redirects when the handler is attached to a web view.
    ///
    /// - Parameter webView: The `WKWebView` being attached.
    @MainActor
    func handleAttach(webView: WKWebView) {

        guard featureFlagger.isFeatureOn(.duckPlayer) else { return }

        setReferrer(webView: webView)

        // Pause Videos if needed
        if duckPlayer.settings.nativeUIYoutubeMode != .never {
            toggleMediaPlayback(webView, pause: true)
        }

        // Attach Navigation Request Observer
        setupYoutubeNavigationRequestObserver(webView: webView)

    }

    /// Updates the referrer after the web view finishes loading a page.
    ///
    /// - Parameter webView: The `WKWebView` that finished loading.
    @MainActor
    func handleDidFinishLoading(webView: WKWebView) {

        guard featureFlagger.isFeatureOn(.duckPlayer) else { return }

        // Update referrer
        setReferrer(webView: webView)
        
    }

    /// Resets settings when the web view starts loading a new page.
    ///
    /// - Parameter webView: The `WKWebView` that started loading.
    @MainActor
    func handleDidStartLoading(webView: WKWebView) {
        // NOOP
    }

    /// Converts a standard YouTube URL to its Duck Player equivalent if applicable.
    ///
    /// - Parameter url: The YouTube `URL` to convert.
    /// - Returns: A Duck Player `URL` if applicable.
    func getDuckURLFor(_ url: URL) -> URL {
        guard let (youtubeVideoID, timestamp) = url.youtubeVideoParams,
                url.isDuckPlayer,
                !url.isDuckURLScheme
        else {
            return url
        }
        return URL.duckPlayer(youtubeVideoID, timestamp: timestamp)
    }

    /// Decides whether to cancel navigation to prevent opening the YouTube app from the web view.
    ///
    /// - Parameters:
    ///   - navigationAction: The `WKNavigationAction` to evaluate.
    ///   - webView: The `WKWebView` where navigation is occurring.
    /// - Returns: `true` if the navigation should be canceled, `false` otherwise.
    @MainActor
    func handleDelegateNavigation(navigationAction: WKNavigationAction, webView: WKWebView) -> Bool {

        setReferrer(webView: webView)

        // Reset lastHandledVideoID
        lastHandledVideoID = nil

        guard let url = navigationAction.request.url else {
            return false
        }

        // Only account for MainFrame navigation
        guard navigationAction.isTargetingMainFrame() else {
            return false
        }

        // Only account for MainFrame navigation
        guard featureFlagger.isFeatureOn(.duckPlayer) else { return false }

        // Stop navigation if we are on SERP and DuckPlayer is enabled for it
        if referrer == .serp &&
            duckPlayer.settings.nativeUISERPEnabled &&
            url.isYoutubeWatch {
                let (videoID, _) = url.youtubeVideoParams ?? ("", nil)
                lastHandledVideoID = videoID
                loadNativeDuckPlayerVideo(videoID: videoID)
                return true
        }

        // Allow everything else
        return false

    }

    /// Sets the host view controller for Duck Player.
    ///
    /// - Parameters:
    ///  - hostViewController: The `DuckPlayerHostingViewControlling` to set as the host.
    @MainActor
    func setHostViewController(_ hostViewController: TabViewController) {
        guard featureFlagger.isFeatureOn(.duckPlayer) else { return }
        isLinkPreview = hostViewController.isLinkPreview
        duckPlayer.setHostViewController(hostViewController)
    }

    /// Handles DuckPlayer Updates when WebView appears
    /// To be implemented based on requested changes
    @MainActor
    func updateDuckPlayerForWebViewAppearance(_ hostViewController: TabViewController) {
        setHostViewController(hostViewController)

        guard featureFlagger.isFeatureOn(.duckPlayer) else { return }
        if let url = hostViewController.tabModel.link?.url, url.isYoutubeWatch {
            if !disableDuckPlayerForNextVideo && !isLinkPreview {
                presentDuckPlayerPill(for: url.youtubeVideoParams?.0 ?? "", timestamp: nil)
            }
        }
    }

    /// Handles DuckPlayer Updates when WebView dissapears
    @MainActor
    func updateDuckPlayerForWebViewDisappearance(_ hostViewController: TabViewController) {
        guard featureFlagger.isFeatureOn(.duckPlayer) else { return }
        duckPlayer.dismissPill(reset: false, animated: false, programatic: true, skipTransition: true)
    }

}
