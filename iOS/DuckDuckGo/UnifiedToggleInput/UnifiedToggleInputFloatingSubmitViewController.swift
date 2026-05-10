//
//  UnifiedToggleInputFloatingSubmitViewController.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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
import DesignResourcesKit
import DesignResourcesKitIcons
import Combine

protocol UnifiedToggleInputFloatingSubmitDelegate: AnyObject {
    func floatingSubmitDidTapSubmit()
    func floatingSubmitDidTapVoice()
}

final class UnifiedToggleInputFloatingSubmitViewController: UIViewController {

    weak var delegate: UnifiedToggleInputFloatingSubmitDelegate?

    private let button: CircularButton = {
        let button = CircularButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isShadowHidden = true
        return button
    }()

    var isAIVoiceChatEnabled = false {
        didSet { updateIcon() }
    }

    private var hasText = false
    private var isFireTab = false
    private var cancellables = Set<AnyCancellable>()

    func refreshFireMode(fireMode: Bool) {
        isFireTab = fireMode
        updateIcon()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.addSubview(button)

        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: Metrics.buttonSize + Metrics.trailingPadding),

            button.widthAnchor.constraint(equalToConstant: Metrics.buttonSize),
            button.heightAnchor.constraint(equalToConstant: Metrics.buttonSize),
            button.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Metrics.trailingPadding),
            button.topAnchor.constraint(equalTo: view.topAnchor),
            button.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        button.addTarget(self, action: #selector(buttonTapped), for: .touchUpInside)
        updateIcon()
    }

    func subscribe(to textPublisher: AnyPublisher<String, Never>) {
        textPublisher
            .map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hasText in
                self?.hasText = hasText
                self?.updateIcon()
            }
            .store(in: &cancellables)
    }

    private func updateIcon() {
        let showVoice = !hasText && isAIVoiceChatEnabled
        let isActive = hasText || showVoice
        let icon = showVoice ? DesignSystemImages.Glyphs.Size24.voice : DesignSystemImages.Glyphs.Size24.arrowUp
        button.setImage(icon, for: .normal)
        button.isEnabled = isActive
        if showVoice {
            button.applyAIVoiceChatStyle()
        } else {
            button.applySubmitStyle(isActive: isActive,
                                    isFireTab: isFireTab,
                                    activeForeground: UIColor(designSystemColor: .accentContentPrimary))
        }
    }

    @objc private func buttonTapped() {
        if hasText {
            delegate?.floatingSubmitDidTapSubmit()
        } else if isAIVoiceChatEnabled {
            delegate?.floatingSubmitDidTapVoice()
        }
    }

    private enum Metrics {
        static let buttonSize: CGFloat = 40
        static let trailingPadding: CGFloat = 16
    }
}
