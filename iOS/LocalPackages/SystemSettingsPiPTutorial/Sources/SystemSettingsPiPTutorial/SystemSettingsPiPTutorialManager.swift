//
//  SystemSettingsPiPTutorialManager.swift
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

import AVFoundation
import AVKit
import Combine

/// Manages PiP tutorial playback and navigation within system settings.
///
/// This class coordinates video playback, URL provider management, and system settings navigation for PiP tutorials.
@MainActor
public final class SystemSettingsPiPTutorialManager {
    weak var presenter: SystemSettingsPiPTutorialPresenting?

    private let playerViewProvider: () -> UIView
    private let videoPlayerProvider: () -> SystemSettingsPiPTutorialPlayer

    private lazy var playerView: UIView = playerViewProvider()
    private lazy var videoPlayer: SystemSettingsPiPTutorialPlayer = videoPlayerProvider()

    private let pipTutorialURLProvider: SystemSettingsPiPTutorialURLManaging
    private let urlOpener: SystemSettingsPiPURLOpener
    private let eventMapper: SystemSettingsPiPTutorialEventMapper

    private var playerItemStatusCancellable: AnyCancellable?

    /// Creates a new PiP tutorial manager with the specified dependencies.
    ///
    /// - Parameters:
    ///   - playerView: The view that will display the video content.
    ///   - videoPlayer: The player responsible for video playback and PiP functionality.
    public convenience init(
        playerView: @escaping @autoclosure () -> UIView,
        videoPlayer: @escaping @autoclosure () -> SystemSettingsPiPTutorialPlayer,
        eventMapper: SystemSettingsPiPTutorialEventMapper
    ) {
        self.init(
            playerView: playerView,
            videoPlayer: videoPlayer,
            pipTutorialURLProvider: SystemSettingsPiPTutorialURLProvider(),
            eventMapper: eventMapper,
            urlOpener: UIApplication.shared
        )
    }

    init(
        playerView: @escaping () -> UIView,
        videoPlayer: @escaping () -> SystemSettingsPiPTutorialPlayer,
        pipTutorialURLProvider: SystemSettingsPiPTutorialURLManaging,
        eventMapper: SystemSettingsPiPTutorialEventMapper,
        urlOpener: SystemSettingsPiPURLOpener
    ) {
        self.playerViewProvider = playerView
        self.videoPlayerProvider = videoPlayer
        self.pipTutorialURLProvider = pipTutorialURLProvider
        self.urlOpener = urlOpener
        self.eventMapper = eventMapper
    }
}

// MARK: - Private

private extension SystemSettingsPiPTutorialManager {

    func loadAndPlayPiPTutorialIfEnabled(for destination: SystemSettingsPiPTutorialDestination) {
        // If PiP is supported, otherwise load the URL without loading the video.
        guard videoPlayer.isPictureInPictureSupported() else {
            urlOpener.open(destination.url)
            return
        }
        
        do {
            let pipTutorialURL = try pipTutorialURLProvider.url(for: destination)

            // Observe status before loading
            playerItemStatusCancellable = videoPlayer.playerItemStatusPublisher
                .receive(on: DispatchQueue.main)
                .filter { $0 == .readyToPlay || $0 == .failed } // We're only interested if the item is ready to play or can't be played.
                .prefix(1) // If video loops `.readyToPlay` is emitted multiple times. We're only interested in the first event when the asset finished loading.
                .sink { [weak self] status in
                    guard let self else { return }
                    switch status {
                    case .readyToPlay:
                        self.videoPlayer.play()
                        Logger.pipTutorial.debug("[PiP Tutorial Video] Opening Default Browser Settings")
                        self.urlOpener.open(destination.url)
                    case .failed:
                        Logger.pipTutorial.error("[PiP Tutorial Video] Could not play PiP video. Opening Default Browser Settings")
                        eventMapper.fireFailedToLoadPiPTutorialEvent(error: videoPlayer.currentItemError, urlPath: videoPlayer.currentItemURL?.absoluteString)
                        self.urlOpener.open(destination.url)
                    default:
                        break
                    }
                }

            // Attach the player before call loading.
            // The player view is removed when the app comes to foreground so there's no need to remove it if the player fails to load the asset.
            // There are intermittent issues when attaching the player view just before playing causing PiP not to show. This ensure PiP will be always visible when we play the video.
            presenter?.attachPlayerView(playerView)
            videoPlayer.load(url: pipTutorialURL)

        } catch {
            logError(error)
            urlOpener.open(destination.url)
        }
    }

    private func logError(_ error: Error) {
        switch error {
        case SystemSettingsPiPTutorialURLProviderError.noProviderAvailable(let destination):
            Logger.pipTutorial.error("Provider for \(destination.identifier.value) not found.")
        case SystemSettingsPiPTutorialURLProviderError.providerError(let error):
            Logger.pipTutorial.error("Provider failed to resolve URL. Error: \(error.localizedDescription)")
        default:
            Logger.pipTutorial.error("An unexpected error occurred: \(error.localizedDescription)")
            eventMapper.fireFailedToLoadPiPTutorialEvent(error: error, urlPath: videoPlayer.currentItemURL?.absoluteString)
        }
    }

}

// MARK: - SystemSettingsPiPTutorialProviderRegistering

extension SystemSettingsPiPTutorialManager: SystemSettingsPiPTutorialProviderRegistering {

    public func register(_ provider: PiPTutorialURLProvider, for destination: SystemSettingsPiPTutorialDestination) {
        pipTutorialURLProvider.register(provider, for: destination)
    }
}

// MARK: - SystemSettingsPiPTutorialManaging

extension SystemSettingsPiPTutorialManager: SystemSettingsPiPTutorialManaging {

    public func setPresenter(_ presenter: SystemSettingsPiPTutorialPresenting) {
        self.presenter = presenter
    }

    public func stopPiPTutorialIfNeeded() {
        // Do not check for feature enabled here as it may be turned off when the video is already playing and we may never stop the video.
        videoPlayer.stop()
        presenter?.detachPlayerView(playerView)
    }

    public func playPiPTutorialAndNavigateTo(destination: SystemSettingsPiPTutorialDestination) {
        loadAndPlayPiPTutorialIfEnabled(for: destination)
    }
    
}
