//
//  DaxLogoManager.swift
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
import UIKit
import SwiftUI

/// Manages the Dax logo view display and positioning
final class DaxLogoManager {
    
    // MARK: - Properties

    private(set) var logoView: UIView = DaxLogoView()

    // MARK: - Public Methods
    
    func installInViewController(_ viewController: UIViewController, belowView topView: UIView) {

        viewController.view.addSubview(logoView)
        logoView.translatesAutoresizingMaskIntoConstraints = false
        logoView.setContentHuggingPriority(.defaultHigh, for: .vertical)

        let centeringGuide = UILayoutGuide()
        centeringGuide.identifier = "DaxLogoCenteringGuide"
        viewController.view.addLayoutGuide(centeringGuide)

        NSLayoutConstraint.activate([

            // Position layout centering guide vertically between top view and keyboard
            viewController.view.leadingAnchor.constraint(equalTo: centeringGuide.leadingAnchor),
            viewController.view.trailingAnchor.constraint(equalTo: centeringGuide.trailingAnchor),
            topView.bottomAnchor.constraint(equalTo: centeringGuide.topAnchor),
            viewController.view.keyboardLayoutGuide.topAnchor.constraint(equalTo: centeringGuide.bottomAnchor),

            // Center within the layout guide
            logoView.topAnchor.constraint(greaterThanOrEqualTo: centeringGuide.topAnchor),
            logoView.bottomAnchor.constraint(lessThanOrEqualTo: centeringGuide.bottomAnchor),
            logoView.leadingAnchor.constraint(greaterThanOrEqualTo: centeringGuide.leadingAnchor),
            logoView.trailingAnchor.constraint(lessThanOrEqualTo: centeringGuide.trailingAnchor),
            logoView.centerXAnchor.constraint(equalTo: centeringGuide.centerXAnchor),
            logoView.centerYAnchor.constraint(equalTo: centeringGuide.centerYAnchor)
        ])

        viewController.view.sendSubviewToBack(logoView)
    }
}

private final class DaxLogoView: UIView {
    let logoImage = UIImageView(image: UIImage(resource: .home))
    let textImage = UIImageView(image: UIImage(resource: .textDuckDuckGo))

    private let stackView = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)

        setUpSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setUpSubviews() {
        stackView.addArrangedSubview(logoImage)
        stackView.addArrangedSubview(textImage)

        textImage.tintColor = UIColor(designSystemColor: .textPrimary)

        stackView.spacing = Metrics.spacing
        stackView.axis = .vertical

        addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
            logoImage.heightAnchor.constraint(lessThanOrEqualToConstant: Metrics.maxLogoSize),
            logoImage.heightAnchor.constraint(equalToConstant: Metrics.maxLogoSize).withPriority(.defaultHigh)
        ])

        logoImage.contentMode = .scaleAspectFit
        textImage.contentMode = .center

    }

    private struct Metrics {
        static let maxLogoSize: CGFloat = 96
        static let spacing: CGFloat = 12
    }
}
