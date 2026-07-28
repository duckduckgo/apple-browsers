//
//  BrowserToolbarView.swift
//  DuckDuckGo
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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

/// Custom bottom toolbar container (replaces `UIToolbar`) with widened touch targets matching legacy `HitTestingToolbar` behavior.
final class BrowserToolbarView: UIView {

    static let extendedHitWidth: CGFloat = 45
    static let legacyButtonsHeight: CGFloat = 49

    private static let horizontalEdgePadding: CGFloat = 8
    private static let buttonRowHorizontalPadding: CGFloat = 20

    private let backgroundView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let buttonStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.distribution = .equalCentering
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(
            top: 0,
            left: BrowserToolbarView.buttonRowHorizontalPadding,
            bottom: 0,
            right: BrowserToolbarView.buttonRowHorizontalPadding)
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private var isLegacyBackgroundTransparent = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        addSubview(backgroundView)
        backgroundView.addSubview(buttonStack)

        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
            backgroundView.heightAnchor.constraint(equalToConstant: Self.legacyButtonsHeight),
            buttonStack.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: Self.horizontalEdgePadding),
            buttonStack.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -Self.horizontalEdgePadding),
            buttonStack.topAnchor.constraint(equalTo: backgroundView.topAnchor),
            buttonStack.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor),
        ])

        applyBackgroundColor()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var arrangedToolbarButtonViews: [UIView] {
        buttonStack.arrangedSubviews
    }

    func setLegacyBackgroundTransparent(_ transparent: Bool) {
        guard isLegacyBackgroundTransparent != transparent else { return }
        isLegacyBackgroundTransparent = transparent
        applyBackgroundColor()
    }

    func setToolbarButtons(_ views: [UIView]) {
        buttonStack.arrangedSubviews.forEach {
            buttonStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        for view in views {
            buttonStack.addArrangedSubview(view)
        }
    }

    private func applyBackgroundColor() {
        backgroundView.backgroundColor = isLegacyBackgroundTransparent ? .clear : ThemeManager.shared.currentTheme.barBackgroundColor
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard !isHidden, alpha >= 0.01, isUserInteractionEnabled else { return false }
        return bounds.contains(point)
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha >= 0.01, isUserInteractionEnabled else { return nil }

        for subview in buttonStack.arrangedSubviews {
            let location = convert(point, to: subview)
            if let hit = subview.hitTest(location, with: event) {
                return hit
            }
            let extra = max(0, Self.extendedHitWidth - subview.bounds.width)
            if location.x >= -extra && location.x <= Self.extendedHitWidth
                && location.y > 0 && location.y <= subview.bounds.height {
                return subview
            }
        }
        return super.hitTest(point, with: event)
    }
}
