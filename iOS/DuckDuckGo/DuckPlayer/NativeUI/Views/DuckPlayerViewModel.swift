//
//  DuckPlayerViewModel.swift
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

import Combine
import Foundation
import UIKit
import WebKit

/// A view model that manages the state and behavior of the DuckPlayer video player.
/// 
/// The DuckPlayerViewModel handles:
/// - YouTube video URL generation with privacy-preserving parameters
/// - Device orientation changes to adapt the player UI
/// - Navigation to YouTube when requested
/// - Autoplay settings management
@MainActor
final class DuckPlayerViewModel: ObservableObject {

    /// Constants used for YouTube URL generation and parameters
    enum Constants {
        /// Base URL for privacy-preserving YouTube embeds
        static let baseURL = "https://www.youtube-nocookie.com/embed/"

        // URL Parameters
        /// Controls whether related videos are shown
        static let relParameter = "rel"
        /// Controls whether video plays inline or fullscreen on iOS
        static let playsInlineParameter = "playsinline"
        /// Controls whether video autoplays when loaded
        static let autoplayParameter = "autoplay"
        // Used to enable features in URL parameters        
        static let enabled = "1"
        static let disabled = "0"
        // Used to set the start time of the video
        static let startParameter = "start"

        // Used to force the player to use a stable version of the player
        // https://app.asana.com/0/1204099484721401/1209718564423105/f
        static let colorSchemeParameter = "color"
        static let colorSchemeValue = "white"
    }

    /// A publisher to notify when Youtube navigation is required.
    /// Emits the videoID that should be opened in YouTube.
    let youtubeNavigationRequestPublisher = PassthroughSubject<String, Never>()

    /// A publisher to notify when the settings button is pressed.    
    let settingsRequestPublisher = PassthroughSubject<Void, Never>()

    /// A publisher to notify when the view is dismissed
    let dismissPublisher = PassthroughSubject<TimeInterval, Never>()

    /// The YouTube video ID to be played
    let videoID: String

    /// Default parameters applied to all YouTube video URLs
    let defaultParameters: [String: String] = [
        Constants.relParameter: Constants.disabled,
        Constants.playsInlineParameter: Constants.enabled,
        Constants.colorSchemeParameter: Constants.colorSchemeValue
    ]

    /// The referrer for the DuckPlayer
    let source: DuckPlayer.VideoNavigationSource

    /// App settings instance for accessing user preferences
    var appSettings: AppSettings

    /// Whether the "Watch in YouTube" button should be visible
    /// This is only shown for SERP videos as otherwise the video is already on YouTube    
    var shouldShowYouTubeButton: Bool {
        !isLandscape && source == .serp
    }

    /// Whether the auto-open on YouTube toggle should be visible
    /// This is hidden in landscape mode or when explicitly set to hidden
    var shouldShowAutoOpenToggle: Bool {
        !isLandscape && showAutoOpenOnYoutubeToggle
    }

    var cancellables = Set<AnyCancellable>()

    /// The DuckPlayer instance
    weak var duckPlayer: DuckPlayerControlling?

    /// The generated URL for the embedded YouTube player
    @Published private(set) var url: URL?
    @Published private(set) var timestamp: TimeInterval = 0

    // Automatic open on Youtube toggle
    @Published var showAutoOpenOnYoutubeToggle: Bool = true
    @Published var autoOpenOnYoutube: Bool = false {
        didSet {
            appSettings.duckPlayerNativeYoutubeMode = autoOpenOnYoutube ? .auto : .ask
        }
    }

    /// Current interface orientation state.
    /// - `true` when device is in landscape orientation
    /// - `false` when device is in portrait orientation
    @Published var isLandscape: Bool = false

    // MARK: - Private Properties
    private var timestampUpdateTimer: Timer?
    private var webView: WKWebView?
    private var coordinator: DuckPlayerWebView.Coordinator?

    /// Creates a new DuckPlayerViewModel instance
    /// - Parameters:
    ///   - videoID: The YouTube video ID to be played
    ///   - appSettings: App settings instance for accessing user preferences
    init(videoID: String, timestamp: TimeInterval? = nil, appSettings: AppSettings = AppDependencyProvider.shared.appSettings, source: DuckPlayer.VideoNavigationSource = .other) {
        self.videoID = videoID
        self.appSettings = appSettings
        self.timestamp = timestamp ?? 0
        self.source = source
        self.autoOpenOnYoutube = appSettings.duckPlayerNativeYoutubeMode == .auto
        self.url = getVideoURL()
    }

    /// Gets the current video URL with the current timestamp
    /// - Returns: URL with the current timestamp parameter
    func getVideoURL() -> URL? {
        guard let videoURL = getVideoURLWithParameters() else { return nil }
        var components = URLComponents(url: videoURL, resolvingAgainstBaseURL: true)
        let seconds = Int(timestamp)
        var queryItems = components?.queryItems ?? []
        queryItems.append(URLQueryItem(name: Constants.startParameter, value: String(seconds)))
        components?.queryItems = queryItems
        return components?.url
    }

    /// Handles navigation requests to YouTube
    /// - Parameter url: The YouTube video URL to navigate to
    func handleYouTubeNavigation(_ url: URL) {
        if let (videoID, _) = url.youtubeVideoParams {
            youtubeNavigationRequestPublisher.send(videoID)
        }
    }

    /// Opens the current video in the YouTube app or website
    func openInYouTube() {
        youtubeNavigationRequestPublisher.send(videoID)
    }

    /// Called when the view first appears
    /// Sets up orientation monitoring
    func onFirstAppear() {
        updateOrientation()
        NotificationCenter.default.addObserver(self,
                                             selector: #selector(handleOrientationChange),
                                             name: UIDevice.orientationDidChangeNotification,
                                             object: nil)
    }

    /// Called each time the view appears
    func onAppear() {
        // Reserved for future use
    }

    /// Called when the view disappears
    /// Removes orientation monitoring
    func onDisappear() {
        dismissPublisher.send(timestamp)
        stopObservingTimestamp()
        NotificationCenter.default.removeObserver(self,
                                                name: UIDevice.orientationDidChangeNotification,
                                                object: nil)
    }

    /// Updates the current interface orientation state
    func updateOrientation() {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            let newIsLandscape = windowScene.interfaceOrientation.isLandscape
            isLandscape = newIsLandscape

            // Update toggle visibility based on orientation
            if newIsLandscape {
                // Hide toggle in landscape mode
                showAutoOpenOnYoutubeToggle = false
            } else if !showAutoOpenOnYoutubeToggle && !autoOpenOnYoutube {
                // Restore toggle visibility in portrait mode if it wasn't explicitly hidden
                // and auto-open is not enabled
                showAutoOpenOnYoutubeToggle = true
            }
        }
    }

    // Opens the settings view
    func openSettings() {
        settingsRequestPublisher.send()
    }

    /// Starts observing the video timestamp
    /// - Parameter webView: The WKWebView instance playing the video
    /// - Parameter coordinator: The coordinator instance managing the webview
    func startObservingTimestamp(webView: WKWebView, coordinator: DuckPlayerWebView.Coordinator) {
        self.webView = webView
        self.coordinator = coordinator

        timestampUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task {
                if let timestamp = await self.coordinator?.getCurrentTimestamp(webView) {
                    await MainActor.run {
                        self.timestamp = timestamp
                    }
                }
            }
        }
    }

    /// Stops observing the video timestamp
    func stopObservingTimestamp() {
        timestampUpdateTimer?.invalidate()
        timestampUpdateTimer = nil
        webView = nil
        coordinator = nil
    }

    // MARK: - Public Methods

    /// Hides the auto-open toggle UI element
    func hideAutoOpenToggle() {
        showAutoOpenOnYoutubeToggle = false
    }

    // MARK: - Private Methods

    /// Handles device orientation change notifications
    @objc private func handleOrientationChange() {
        updateOrientation()
    }

    /// Generates the URL for the YouTube video with appropriate parameters
    /// - Returns: A URL configured for the embedded YouTube player with privacy-preserving parameters
    private func getVideoURLWithParameters() -> URL? {
        var parameters = defaultParameters
        parameters[Constants.autoplayParameter] = appSettings.duckPlayerAutoplay ? Constants.enabled : Constants.disabled
        let queryString = parameters.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        return URL(string: "\(Constants.baseURL)\(videoID)?\(queryString)")
    }

}
