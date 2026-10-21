//
//  UnifiedToggleInputFloatingReturnKeyViewController.swift
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
import DesignResourcesKitIcons

protocol UnifiedToggleInputFloatingReturnKeyDelegate: AnyObject {
    func floatingReturnKeyDidTap()
}

struct UnifiedToggleInputFloatingReturnKeyState: Equatable {
    let hasText: Bool
    let mode: TextEntryMode
    let usesFloatingReturnKey: Bool

    static let empty = UnifiedToggleInputFloatingReturnKeyState(
        hasText: false,
        mode: .aiChat,
        usesFloatingReturnKey: false
    )

    init(
        hasText: Bool,
        mode: TextEntryMode = .aiChat,
        usesFloatingReturnKey: Bool = false
    ) {
        self.hasText = hasText
        self.mode = mode
        self.usesFloatingReturnKey = usesFloatingReturnKey
    }

    init(
        text: String,
        mode: TextEntryMode,
        usesFloatingReturnKey: Bool
    ) {
        self.hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        self.mode = mode
        self.usesFloatingReturnKey = usesFloatingReturnKey
    }

    var canInsertReturn: Bool {
        mode == .aiChat && usesFloatingReturnKey && hasText
    }
}

final class UnifiedToggleInputFloatingReturnKeyViewController: UIViewController {

    weak var delegate: UnifiedToggleInputFloatingReturnKeyDelegate?

    private let button: CircularButton = {
        let button = CircularButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isShadowHidden = true
        button.setImage(DesignSystemImages.Glyphs.Size24.enter, for: .normal)
        button.applyReturnKeyStyle()
        button.isEnabled = true
        return button
    }()

    private var returnKeyState = UnifiedToggleInputFloatingReturnKeyState.empty

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

    func updateState(_ state: UnifiedToggleInputFloatingReturnKeyState) {
        returnKeyState = state
        updateIcon()
    }

    private func updateIcon() {
        button.setImage(DesignSystemImages.Glyphs.Size24.enter, for: .normal)
        button.isEnabled = returnKeyState.canInsertReturn
        button.applyReturnKeyStyle()
    }

    @objc private func buttonTapped() {
        if returnKeyState.canInsertReturn {
            delegate?.floatingReturnKeyDidTap()
        }
    }

    private enum Metrics {
        static let buttonSize: CGFloat = 44
        static let trailingPadding: CGFloat = 16
    }
}
