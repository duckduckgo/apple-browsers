//
//  SystemSettingsPiPTutorialService.swift
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

import Foundation
import protocol BrowserServicesKit.FeatureFlagger
import class UIKit.UIApplication
import SystemSettingsPiPTutorial

@MainActor
final class SystemSettingsPiPTutorialService {
    let manager: SystemSettingsPiPTutorialManager

    init(featureFlagger: FeatureFlagger) {
        // Initialises the Video Player Coordinator and assign the avPlayerLayer to PiP controller.
        let videoPlayerCoordinator = VideoPlayerCoordinator(configuration: .init(allowsPictureInPicturePlayback: true, requiresLinearPlayback: true))
        let playerView = PlayerUIView(player: videoPlayerCoordinator.player)
        videoPlayerCoordinator.setupPictureInPicture(playerLayer: playerView.playerLayer)

        let isFeatureEnabled = {
            true
        }

        manager = SystemSettingsPiPTutorialManager(
            playerView: playerView,
            videoPlayer: videoPlayerCoordinator,
            eventMapper: SystemSettingsPiPTutorialPixelHandler()
        )

        // Register PiP Video URL providers
        registerAllURLProviders(featureFlagger: featureFlagger)
    }

}

// MARK: - Private

private extension SystemSettingsPiPTutorialService {

    func registerAllURLProviders(featureFlagger: FeatureFlagger) {

        // Register PiP URL Tutorial Provider for 'Set As Default' Browser destination.
        if featureFlagger.isFeatureOn(.setAsDefaultBrowserPiPVideoTutorial) {
            manager.register(DefaultBrowserPiPTutorialURLProvider(), for: .defaultBrowser)
        }

    }
}

// MARK: - App States Lifecycle

extension SystemSettingsPiPTutorialService {

    // Called when App State change to Foreground.
    // This will ensure that PiP is stopped when the app comes to foreground if a PiP session is active.
    func resume() {
        manager.stopPiPTutorialIfNeeded()
    }

}

extension SystemSettingsPiPTutorialService {

    func setPresenter(_ presenter: SystemSettingsPiPTutorialPresenting) {
        manager.setPresenter(presenter)
    }

}

// MARK: - PiP Destinations

extension SystemSettingsPiPTutorialDestination {

    enum Identifiers: String {
        case defaultBrowser
    }

    static let defaultBrowser = SystemSettingsPiPTutorialDestination(
        identifier: Identifiers.defaultBrowser.rawValue,
        url: URL(string: UIApplication.openSettingsURLString)!
    )

}
