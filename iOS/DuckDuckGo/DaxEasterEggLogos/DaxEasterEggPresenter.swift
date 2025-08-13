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

/// Presents Dax Easter Egg logos in full-screen mode with zoom transitions.
protocol DaxEasterEggPresenting {
    /// Pre-loads the full resolution image for smoother transitions when presented.
    func preloadFullResolutionImage(for url: URL)
    
    /// Presents the logo in full-screen mode with a custom zoom transition.
    /// Automatically handles image preloading and caching for smooth animations.
    func presentFullScreen(from presentingViewController: UIViewController,
                           logoURL: URL?,
                           currentImage: UIImage?,
                           sourceFrame: CGRect)
}

/// Presents Dax Easter Egg logos in full-screen mode with image caching and zoom transitions.
final class DaxEasterEggPresenter: DaxEasterEggPresenting {
    
    private let imageManager: DaxEasterEggImageManaging
    
    init(imageManager: DaxEasterEggImageManaging = DaxEasterEggImageManager()) {
        self.imageManager = imageManager
    }
    
    func preloadFullResolutionImage(for url: URL) {
        imageManager.preloadFullResolutionImage(for: url)
    }
    
    func presentFullScreen(from presentingViewController: UIViewController,
                           logoURL: URL?,
                           currentImage: UIImage?,
                           sourceFrame: CGRect) {
        
        if let url = logoURL {
            imageManager.getBestImageForFullScreen(url: url, fallbackImage: currentImage) { [weak presentingViewController] _ in
                self.presentFullScreenViewController(
                    from: presentingViewController,
                    logoURL: url,
                    placeholderImage: currentImage,
                    sourceFrame: sourceFrame,
                    transitionImage: currentImage
                )
            }
        } else {
            presentFullScreenViewController(
                from: presentingViewController,
                logoURL: nil,
                placeholderImage: currentImage,
                sourceFrame: sourceFrame,
                transitionImage: currentImage
            )
        }
    }
    
    private func presentFullScreenViewController(from presentingViewController: UIViewController?,
                                                 logoURL: URL?,
                                                 placeholderImage: UIImage?,
                                                 sourceFrame: CGRect,
                                                 transitionImage: UIImage?) {
        guard let presentingViewController = presentingViewController else { return }
        
        let fullScreenController = DaxEasterEggFullScreenViewController(
            imageURL: logoURL,
            placeholderImage: placeholderImage,
            sourceFrame: sourceFrame,
            sourceImage: transitionImage
        )
        presentingViewController.present(fullScreenController, animated: true)
    }
}
