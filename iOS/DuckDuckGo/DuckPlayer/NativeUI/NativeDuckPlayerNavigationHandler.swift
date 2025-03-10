//
//  DuckPlayerNavigationHandler.swift
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

    /// Delegate for handling tab navigation events.
    weak var tabNavigationHandler: DuckPlayerTabNavigationHandling?

    /// Cancellable for observing DuckPlayer Mode changes
    @MainActor private var duckPlayerModeCancellable: AnyCancellable?

    /// Cancellable for observing DuckPlayer Navigation Request
    @MainActor private var duckPlayerNavigationRequestCancellable: AnyCancellable?

    /// Cancellable for observing DuckPlayer dismissal
    @MainActor private var duckPlayerDismissalCancellable: AnyCancellable?

    /// JavaScript for media playback control
    private let mediaControlScript: String = {
        guard let url = Bundle.main.url(forResource: "mediaControl", withExtension: "js"),
              let script = try? String(contentsOf: url) else {
            assertionFailure("Failed to load mute audio script")
            return ""
        }
        return script
    }()

    /// Script to mute/unmute audio
    private let muteAudioScript: String = {
        guard let url = Bundle.main.url(forResource: "muteAudio", withExtension: "js"),
              let script = try? String(contentsOf: url) else {
            assertionFailure("Failed to load mute audio script")
            return ""
        }
        return script
    }()

    private struct Constants {
        static let SERPURL =  "duckduckgo.com/"
        static let refererHeader = "Referer"
        static let templateName = "index"
        static let duckPlayerAlwaysString = "always"
        static let duckPlayerDefaultString = "default"
        static let settingsKey = "settings"
        static let httpMethod = "GET"
        static let watchInYoutubeVideoParameter = "v"
        static let youtubeEmbedURI = "embeds_referring_euri"
        static let youtubeScheme = "youtube://"
        static let duckPlayerScheme = URL.NavigationalScheme.duck.rawValue
        static let duckPlayerReferrerParameter = "dp_referrer"
        static let newTabParameter = "dp_isNewTab"
    }

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
         pixelFiring: PixelFiring.Type = Pixel.self,
         dailyPixelFiring: DailyPixelFiring.Type = DailyPixel.self,
         tabNavigationHandler: DuckPlayerTabNavigationHandling? = nil) {
        self.duckPlayer = duckPlayer
        self.featureFlagger = featureFlagger
        self.appSettings = appSettings
        self.tabNavigationHandler = tabNavigationHandler
        super.init()
    }

    deinit {
        duckPlayerModeCancellable?.cancel()
        duckPlayerNavigationRequestCancellable?.cancel()
        duckPlayerDismissalCancellable?.cancel()
    }

   
    /// Checks if the Duck Player feature is enabled via feature flags.
    private var isDuckPlayerFeatureEnabled: Bool {
        featureFlagger.isFeatureOn(.duckPlayer)
    }

    /// Determines if "Open in New Tab" for Duck Player is enabled in the settings.
    private var isOpenInNewTabEnabled: Bool {
        featureFlagger.isFeatureOn(.duckPlayer) && featureFlagger.isFeatureOn(.duckPlayerOpenInNewTab) && duckPlayer.settings.openInNewTab && duckPlayerMode != .disabled
    }

    /// Retrieves the current mode of Duck Player based on feature flags and user settings.
    private var duckPlayerMode: DuckPlayerMode {
        let isEnabled = isDuckPlayerFeatureEnabled
        return isEnabled ? duckPlayer.settings.mode : .disabled
    }

    /// Checks if the YouTube app is installed on the device.
    private var isYouTubeAppInstalled: Bool {
        if let youtubeURL = URL(string: Constants.youtubeScheme) {
            return UIApplication.shared.canOpenURL(youtubeURL)
        }
        return false
    }

   

    /// Redirects the web view to play the video in Duck Player, optionally forcing a new tab.
    ///
    /// - Parameters:
    ///   - url: The URL of the video.
    ///   - webView: The `WKWebView` to load the content into.
    ///   - forceNewTab: Whether to force opening in a new tab.
    ///   - disableNewTab: Ignore openInNewTab settings
    @MainActor
    private func redirectToDuckPlayerVideo(url: URL?, webView: WKWebView, forceNewTab: Bool = false, disableNewTab: Bool = false) {

        guard let url,
              let (videoID, _) = url.youtubeVideoParams else { return }

        // Mute audio for the opening tab if required
        // This prevents opening tab from hijacking Audio Session
        // and playing audio in the background
        toggleAudioForTab(webView, mute: true)

        // Pause all media elements in the webView
        toggleMediaPlayback(webView, pause: true)

        // Load the native DuckPlayer video
        loadNativeDuckPlayerVideo(videoID: videoID)

        // Subscribe to player dismissal
        duckPlayerDismissalCancellable = duckPlayer.playerDismissedPublisher
            .sink { [weak self] in
                self?.allowYoutubeVideoPlayback(webView: webView)
            }

        return
    }
   

    @MainActor
    private func loadNativeDuckPlayerVideo(videoID: String) {
        // Only allow native UI on iPhone
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }

        if referrer == .youtube {
            duckPlayer.loadNativeDuckPlayerVideo(videoID: videoID, source: .youtube, timestamp: nil)
        } else {
            duckPlayer.loadNativeDuckPlayerVideo(videoID: videoID, source: .other, timestamp: nil)
        }
    }

    /// Toggles audio playback for a specific webView.
    ///
    /// - Parameters:
    ///  - webView: The `WKWebView` to manipulate.
    ///  - mute: Whether to mute the audio.
    @MainActor
    private func toggleAudioForTab(_ webView: WKWebView, mute: Bool) {
        if duckPlayer.settings.openInNewTab || duckPlayer.settings.nativeUI {
            webView.evaluateJavaScript("\(muteAudioScript)(\(mute))")
        }
    }

    /// Sets the referrer based on the current web view URL to aid in analytics.
    ///
    /// - Parameter webView: The `WKWebView` whose URL is used to determine the referrer.
    private func setReferrer(webView: WKWebView) {

        // Make sure we are NOT DuckPlayer
        guard let url = webView.url, !url.isDuckPlayer else { return }

        // First, try to use the back Item
        var backItems = webView.backForwardList.backList.reversed()

        // Ignore any previous URL that's duckPlayer or youtube-no-cookie
        if backItems.first?.url != nil, url.isDuckPlayer {
            backItems = webView.backForwardList.backList.dropLast().reversed()
        }

        // If the current URL is DuckPlayer, use the previous history item
        guard let referrerURL = url.isDuckPlayer ? backItems.first?.url : url else {
            return
        }

        // SERP as a referrer
        if referrerURL.isDuckDuckGoSearch {
            referrer = .serp
            return
        }

        // Set to Youtube for "Watch in Youtube videos"
        if referrerURL.isYoutubeWatch && duckPlayerMode == .enabled && duckPlayer.settings.allowFirstVideo {
            referrer = .youtube
            return
        }

        // Set to Overlay for Always ask
        if referrerURL.isYoutubeWatch && duckPlayerMode == .alwaysAsk {
            referrer = .youtubeOverlay
            return
        }

        // Any Other Youtube URL or other referrer
        if referrerURL.isYoutube {
            referrer = .youtube
            return
        } else {
            referrer = .other
        }

    }

    /// Determines if the current tab is a new tab based on the targetFrame request and other params
    ///
    /// - Parameter navigationAction: The `WKNavigationAction` used to determine the tab type.
    private func isNewTab(_ navigationAction: WKNavigationAction) -> Bool {

        guard let request = navigationAction.targetFrame?.safeRequest,
              let url = request.url else {
            return false
        }

        // Always return false if open in new tab is disabled
        guard isOpenInNewTabEnabled else { return false }

        // If the target frame is duckPlayer itself or there's no URL
        // we're at a new tab
        if url.isDuckPlayer || url.isEmpty {
            return true
        }

        return false
    }

    /// Register a DuckPlayer Youtube Navigation Request observer
    /// Used when DuckPlayer requires direct Youtube Navigation
    @MainActor
    private func setupYoutubeNavigationRequestObserver(webView: WKWebView) {
        duckPlayerNavigationRequestCancellable = duckPlayer.youtubeNavigationRequest
            .sink { [weak self] url in
                //self?.redirectToYouTubeVideo(url: url, webView: webView)
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
            webView.evaluateJavaScript("\(mediaControlScript); mediaControl(\(pause))")
        }
    }

    /// Cleans up timers and audio state when DuckPlayer is dismissed
    @MainActor
    private func allowYoutubeVideoPlayback(webView: WKWebView) {
        toggleMediaPlayback(webView, pause: false)
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

        // Update referrer if needed
        //updateReferrerIfNeeded(url: url)
        
    }

    /// Observes URL changes and redirects to Duck Player when appropriate, avoiding duplicate handling.
    ///
    /// - Parameter webView: The `WKWebView` whose URL has changed.
    /// - Returns: A result indicating whether the URL change was handled.
    // swiftlint:disable cyclomatic_complexity
    @MainActor
    func handleURLChange(webView: WKWebView, previousURL: URL?, newURL: URL?) -> DuckPlayerNavigationHandlerURLChangeResult {

        // Ensure all media playback is allowed by default
        self.toggleMediaPlayback(webView, pause: false)

        // Check if DuckPlayer feature is enabled
        guard isDuckPlayerFeatureEnabled else {
            return .notHandled(.featureOff)
        }

        guard let url = newURL, let (videoID, _) = url.youtubeVideoParams else {
            duckPlayer.dismissPill(reset: true, animated: true)
            return .notHandled(.invalidURL)
        }

        guard url.isYoutubeWatch else {
            duckPlayer.dismissPill(reset: true, animated: true)
            return .notHandled(.isNotYoutubeWatch)
        }

        // Present Duck Player Pill (Native entry point)
        if duckPlayer.settings.mode == .alwaysAsk {

            // Pause video
            Task { await pauseVideoStart(webView: webView) }

            // If we're not in a Watch main page, hide
            // the pill.  Youtube adds #fragments to Watch main pages
            // When presenting settings and preferences
            if !url.isYoutubeWatch {
                duckPlayer.dismissPill(reset: false, animated: true)
            }

            // Present the Pill if needed
            Task { @MainActor in
                // Skip URLs for settings and #fragments
                if url.isYoutubeWatch {
                    duckPlayer.presentPill(for: videoID, timestamp: nil)
                }
            }
        }

        // If this is an internal Youtube Link (i.e Clicking in youtube logo in the player)
        // Do not handle it

        guard duckPlayerMode == .enabled else {
            return .notHandled(.duckPlayerDisabled)
        }

        // Resume media playback by
        toggleMediaPlayback(webView, pause: false)
        return .notHandled(.isNotYoutubeWatch)
    }

    // Temporarily pause media playback during page transition
    // The pause is applied repeatedly for 1 second to ensure it takes effect
    // even if the DOM is changing during early initialization
    // Once the page has loaded, the JS mutation observer takes care
    // Of pausing newly added elements.
    @MainActor
    private func pauseVideoStart(webView: WKWebView) async {
        // First phase: try every 0.05s for 1 second
        Task { @MainActor in
            let startTime = Date()
            while Date().timeIntervalSince(startTime) < 1.0 {
                self.toggleMediaPlayback(webView, pause: true)
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }
    // swiftlint: enable cyclomatic_complexity

    /// Custom back navigation logic to handle Duck Player in the web view's history stack.
    ///
    /// - Parameter webView: The `WKWebView` to navigate back in.
    @MainActor
    func handleGoBack(webView: WKWebView) {

        guard let url = webView.url, url.isDuckPlayer, isDuckPlayerFeatureEnabled else {
            webView.goBack()
            return
        }

        // Check if the back list has items, and if not try to close the tab
        guard !webView.backForwardList.backList.isEmpty else {
            tabNavigationHandler?.closeTab()
            return
        }

        // Find the last non-YouTube video URL in the back list
        let backList = webView.backForwardList.backList
        var nonYoutubeItem: WKBackForwardListItem?

        for item in backList.reversed() where !item.url.isYoutubeVideo && !item.url.isDuckPlayer {
            nonYoutubeItem = item
            break
        }
        
        webView.stopLoading()
        webView.goBack()
      
    }

    /// Handles reload actions, ensuring Duck Player settings are respected during the reload.
    ///
    /// - Parameter webView: The `WKWebView` to reload.
    @MainActor
    func handleReload(webView: WKWebView) {

        // Reset DuckPlayer status
        duckPlayer.settings.allowFirstVideo = false

        guard let url = webView.url else {
            return
        }

        guard isDuckPlayerFeatureEnabled else {
            webView.reload()
            return
        }

        if url.isDuckPlayer, duckPlayerMode != .disabled {
            redirectToDuckPlayerVideo(url: url, webView: webView, disableNewTab: true)
            return
        }

        if url.isYoutubeWatch, duckPlayerMode == .alwaysAsk {
            //redirectToYouTubeVideo(url: url, webView: webView, allowFirstVideo: false, disableNewTab: true)
            return
        }

        webView.reload()

    }

    /// Initializes settings and potentially redirects when the handler is attached to a web view.
    ///
    /// - Parameter webView: The `WKWebView` being attached.
    @MainActor
    func handleAttach(webView: WKWebView) {

        // Stop playback if needed
        if duckPlayerMode == .enabled && duckPlayer.settings.nativeUI {
            toggleMediaPlayback(webView, pause: true)
        }

        // Reset referrer and initial settings
        referrer = .other

        // Attach WebView to OverlayPixels
        //setupPlayerModeObserver()
        setupYoutubeNavigationRequestObserver(webView: webView)

        // Ensure feature and mode are enabled
        guard isDuckPlayerFeatureEnabled,
              let url = webView.url,
              duckPlayerMode == .enabled || duckPlayerMode == .alwaysAsk else {
            return
        }

    }

    /// Updates the referrer after the web view finishes loading a page.
    ///
    /// - Parameter webView: The `WKWebView` that finished loading.
    @MainActor
    func handleDidFinishLoading(webView: WKWebView) {
    }

    /// Resets settings when the web view starts loading a new page.
    ///
    /// - Parameter webView: The `WKWebView` that started loading.
    @MainActor
    func handleDidStartLoading(webView: WKWebView) {

        setReferrer(webView: webView)

    }

    /// Converts a standard YouTube URL to its Duck Player equivalent if applicable.
    ///
    /// - Parameter url: The YouTube `URL` to convert.
    /// - Returns: A Duck Player `URL` if applicable.
    func getDuckURLFor(_ url: URL) -> URL {
        guard let (youtubeVideoID, timestamp) = url.youtubeVideoParams,
                url.isDuckPlayer,
                !url.isDuckURLScheme,
                duckPlayerMode != .disabled
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

        guard let url = navigationAction.request.url else {
            return false
        }

        // Only account for MainFrame navigation
        guard navigationAction.isTargetingMainFrame() else {
            return false
        }

        // Only if DuckPlayer is enabled
        guard isDuckPlayerFeatureEnabled else {
            return false
        }

        // Only account for in 'Always' mode
        if duckPlayerMode == .disabled {
            return false
        }

        // Only account for in 'Duck Player' URL
        if url.isDuckPlayer {
            return false
        }

        // Do not intercept any back/forward navigation
        if navigationAction.navigationType == .backForward {
            return false
        }

        // Ignore YouTube Watch URLs if allowFirst video is set
        if url.isYoutubeWatch && duckPlayer.settings.allowFirstVideo {
            return false
        }

        // Redirect to Duck Player if enabled
        if url.isYoutubeWatch && duckPlayerMode == .enabled {
            redirectToDuckPlayerVideo(url: url, webView: webView)
            return true
        }

        // Redirect to Youtube + DuckPlayer Overlay if Ask Mode
        if url.isYoutubeWatch && duckPlayerMode == .alwaysAsk {
            //redirectToYouTubeVideo(url: url, webView: webView, allowFirstVideo: false, disableNewTab: true)
            return true
        }

        // Allow everything else
        return false

    }

    /// Sets the host view controller for Duck Player.
    ///
    /// - Parameters:
    ///  - hostViewController: The `TabViewController` to set as the host.
    @MainActor
    func setHostViewController(_ hostViewController: TabViewController) {
        duckPlayer.setHostViewController(hostViewController)
    }

    /// Handles DuckPlayer Updates when WebView appears
    /// To be implemented based on requested changes
    @MainActor
    func updateDuckPlayerForWebViewAppearance(_ hostViewController: TabViewController) {
        setHostViewController(hostViewController)
        if let url = hostViewController.tabModel.link?.url, url.isYoutubeWatch {
            self.duckPlayer.presentPill(for: url.youtubeVideoParams?.0 ?? "", timestamp: nil)
        }
    }

    /// Handles DuckPlayer Updates when WebView dissapears
    func updateDuckPlayerForWebViewDisappearance(_ hostViewController: TabViewController) {
        duckPlayer.dismissPill(reset: false, animated: false)
    }

}
