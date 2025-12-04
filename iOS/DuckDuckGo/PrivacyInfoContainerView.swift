//
//  PrivacyInfoContainerView.swift
//  DuckDuckGo
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

/// Delegate for handling privacy info container interactions.
protocol PrivacyInfoContainerViewDelegate: AnyObject {
    /// Called when the user taps a Dax Easter Egg logo in the privacy icon.
    func privacyInfoContainerViewDidTapDaxLogo(_ view: PrivacyInfoContainerView, logoURL: URL?, currentImage: UIImage?, sourceFrame: CGRect)
}

class PrivacyInfoContainerView: UIView {

    private(set) var privacyIcon: PrivacyIconView!
    weak var delegate: PrivacyInfoContainerViewDelegate?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        backgroundColor = .clear
        clipsToBounds = false // Allow privacy icon animations to overflow

        // Create and add privacy icon view
        privacyIcon = PrivacyIconView()
        privacyIcon.translatesAutoresizingMaskIntoConstraints = false
        privacyIcon.delegate = self
        addSubview(privacyIcon)

        // Set up constraints - 28x28 container
        NSLayoutConstraint.activate([
            privacyIcon.widthAnchor.constraint(equalToConstant: 28),
            privacyIcon.heightAnchor.constraint(equalToConstant: 28),
            privacyIcon.centerXAnchor.constraint(equalTo: centerXAnchor),
            privacyIcon.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    var isAnimationPlaying: Bool {
        privacyIcon.isAnimationPlaying
    }
}

// MARK: - PrivacyIconViewDelegate

extension PrivacyInfoContainerView: PrivacyIconViewDelegate {
    func privacyIconViewDidTapDaxLogo(_ view: PrivacyIconView, logoURL: URL?, currentImage: UIImage?, sourceFrame: CGRect) {
        delegate?.privacyInfoContainerViewDidTapDaxLogo(self, logoURL: logoURL, currentImage: currentImage, sourceFrame: sourceFrame)
    }
}
