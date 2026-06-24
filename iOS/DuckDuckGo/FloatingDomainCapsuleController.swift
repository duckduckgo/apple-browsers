//
//  FloatingDomainCapsuleController.swift
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

import DesignResourcesKit
import UIKit

final class FloatingDomainCapsuleController {

    private let onTap: () -> Void
    private let backgroundView = UIVisualEffectView(effect: nil)
    private var topConstraint: NSLayoutConstraint?
    private var bottomConstraint: NSLayoutConstraint?

    private lazy var button: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isHidden = true
        button.alpha = 0
        button.titleLabel?.font = UIFont.daxCaption1()
        button.setTitleColor(UIColor(designSystemColor: .textPrimary), for: .normal)
        button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        button.backgroundColor = .clear
        button.layer.cornerCurve = .continuous
        button.layer.cornerRadius = 14
        button.layer.masksToBounds = true
        button.addTarget(self, action: #selector(onCapsuleTapped), for: .touchUpInside)
        return button
    }()

    init(onTap: @escaping () -> Void) {
        self.onTap = onTap
    }

    func install(in view: UIView) {
        guard button.superview == nil else { return }

        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.isUserInteractionEnabled = false
        backgroundView.layer.cornerCurve = .continuous
        backgroundView.layer.cornerRadius = 14
        backgroundView.clipsToBounds = true
        button.insertSubview(backgroundView, at: 0)

        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: button.topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: button.bottomAnchor)
        ])

        applyGlassStyle()
        view.addSubview(button)
        topConstraint = button.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8)
        bottomConstraint = button.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8)

        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
    }

    func update(addressBarPosition: AddressBarPosition,
                isFloatingUIEnabled: Bool,
                isUnifiedToggleInputActive: Bool,
                isAITab: Bool,
                isMinimalChromeLayout: Bool,
                domain: String?,
                barsVisibilityPercent: CGFloat,
                in view: UIView) {
        let useTopAnchor = addressBarPosition == .top
        topConstraint?.isActive = useTopAnchor
        bottomConstraint?.isActive = !useTopAnchor

        guard isFloatingUIEnabled,
              !isUnifiedToggleInputActive,
              !isAITab,
              !isMinimalChromeLayout,
              let domain,
              !domain.isEmpty else {
            button.alpha = 0
            button.isHidden = true
            return
        }

        let targetAlpha = max(0, min(1, 1 - barsVisibilityPercent))
        guard targetAlpha > 0.01 else {
            button.alpha = 0
            button.isHidden = true
            return
        }

        if button.title(for: .normal) != domain {
            button.setTitle(domain, for: .normal)
        }

        button.isHidden = false
        button.alpha = targetAlpha
        view.bringSubviewToFront(button)
    }

    private func applyGlassStyle() {
        if #available(iOS 26.0, *) {
            backgroundView.effect = UIGlassEffect(style: .regular)
        } else {
            backgroundView.effect = UIBlurEffect(style: .systemThinMaterial)
            backgroundView.contentView.backgroundColor = UIColor(designSystemColor: .surface).withAlphaComponent(0.2)
        }
    }

    @objc
    private func onCapsuleTapped() {
        onTap()
    }
}
