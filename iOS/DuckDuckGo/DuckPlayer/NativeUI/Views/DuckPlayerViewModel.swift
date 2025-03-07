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

/// A view model that manages the state and behavior of the DuckPlayer video player.
/// 
/// The DuckPlayerViewModel handles:
/// - YouTube video URL generation with privacy-preserving parameters
/// - Device orientation changes to adapt the player UI
/// - Navigation to YouTube when requested
/// - Autoplay settings management
final class DuckPlayerViewModel: ObservableObject {

    /// A publisher to notify when Youtube navigation is required.
    /// Emits the videoID that should be opened in YouTube.
    let youtubeNavigationRequestPublisher = PassthroughSubject<String, Never>()

    /// A publisher to notify when the settings button is pressed.    
    let settingsRequestPublisher = PassthroughSubject<Void, Never>()

    /// A publisher to notify when the view is dismissed
    let dismissPublisher = PassthroughSubject<Void, Never>()

    /// Current interface orientation state.
    /// - `true` when device is in landscape orientation
    /// - `false` when device is in portrait orientation
    @Published private var isLandscape: Bool = false

    weak var duckPlayer: DuckPlayerControlling?

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
    }

    /// The YouTube video ID to be played
    let videoID: String

    /// App settings instance for accessing user preferences
    var appSettings: AppSettings

    /// Whether the "Watch in YouTube" button should be visible
    /// Returns `false` when in landscape mode to maximize video viewing area
    var shouldShowYouTubeButton: Bool {
        !isLandscape
    }

    var cancellables = Set<AnyCancellable>()

    /// The generated URL for the embedded YouTube player
    @Published private(set) var url: URL?

    /// Default parameters applied to all YouTube video URLs
    let defaultParameters: [String: String] = [
        Constants.relParameter: Constants.disabled,
        Constants.playsInlineParameter: Constants.enabled
    ]

    /// Creates a new DuckPlayerViewModel instance
    /// - Parameters:
    ///   - videoID: The YouTube video ID to be played
    ///   - appSettings: App settings instance for accessing user preferences
    init(videoID: String, appSettings: AppSettings = AppDependencyProvider.shared.appSettings) {
        self.videoID = videoID
        self.appSettings = appSettings
        self.url = getVideoURL()
    }

    /// Generates the URL for the YouTube video with appropriate parameters
    /// - Returns: A URL configured for the embedded YouTube player with privacy-preserving parameters
    func getVideoURL() -> URL? {
        var parameters = defaultParameters
        parameters[Constants.autoplayParameter] = appSettings.duckPlayerAutoplay ? Constants.enabled : Constants.disabled
        let queryString = parameters.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        return URL(string: "\(Constants.baseURL)\(videoID)?\(queryString)")
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
        dismissPublisher.send()
        NotificationCenter.default.removeObserver(self,
                                                name: UIDevice.orientationDidChangeNotification,
                                                object: nil)
    }

    /// Handles device orientation change notifications
    @objc private func handleOrientationChange() {
        updateOrientation()
    }

    /// Updates the current interface orientation state
    func updateOrientation() {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            isLandscape = windowScene.interfaceOrientation.isLandscape
        }
    }

    // Opens the settings view
    func openSettings() {
        settingsRequestPublisher.send()
    }

}
