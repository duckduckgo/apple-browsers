//
//  DaxEasterEggPresenter.swift
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
import PrivacyConfig

/// Presents Dax Easter Egg logos in full-screen mode with zoom transitions.
protocol DaxEasterEggPresenting {
    /// Presents the logo in full-screen mode with a custom zoom transition.
    func presentFullScreen(from presentingViewController: UIViewController,
                           logoURL: URL?,
                           currentImage: UIImage?,
                           sourceFrame: CGRect,
                           sourceViewController: OmniBarViewController?)
}

/// Presents Dax Easter Egg logos in full-screen mode with zoom transitions.
final class DaxEasterEggPresenter: DaxEasterEggPresenting {

    private let logoStore: DaxEasterEggLogoStoring
    private let featureFlagger: FeatureFlagger

    init(logoStore: DaxEasterEggLogoStoring, featureFlagger: FeatureFlagger) {
        self.logoStore = logoStore
        self.featureFlagger = featureFlagger
    }

    func presentFullScreen(from presentingViewController: UIViewController,
                           logoURL: URL?,
                           currentImage: UIImage?,
                           sourceFrame: CGRect,
                           sourceViewController: OmniBarViewController?) {
        let fullScreenController = DaxEasterEggFullScreenViewController(
            imageURL: logoURL,
            sourceFrame: sourceFrame,
            sourceImage: currentImage,
            sourceViewController: sourceViewController,
            logoStore: logoStore,
            featureFlagger: featureFlagger
        )
        presentingViewController.present(fullScreenController, animated: true)
    }
}
