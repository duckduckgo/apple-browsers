//
//  TabSwitcherTitleBarView.swift
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

final class TabSwitcherTitleBarView: UIView {

    private struct Metrics {
        static let height: CGFloat = 60
        static let buttonSize: CGFloat = 44
        static let stackSpacing: CGFloat = 16
        static let horizontalPadding: CGFloat = 16
        static let bottomBarVerticalOffset: CGFloat = 2
    }

    let titleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.daxHeadline()
        label.textColor = UIColor(designSystemColor: .textPrimary)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    let leadingButtonsStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = Metrics.stackSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    let trailingButtonsStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = Metrics.stackSpacing
        stack.semanticContentAttribute = .forceRightToLeft
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let centerContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private weak var currentCenterView: UIView?
    private var managedButtonConstraints: [UIView: [NSLayoutConstraint]] = [:]

    private var leadingStackCenterY: NSLayoutConstraint!
    private var trailingStackCenterY: NSLayoutConstraint!
    private var centerContainerCenterY: NSLayoutConstraint!

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
        translatesAutoresizingMaskIntoConstraints = false

        addSubview(leadingButtonsStack)
        addSubview(trailingButtonsStack)
        addSubview(centerContainer)
        centerContainer.addSubview(titleLabel)

        let heightConstraint = heightAnchor.constraint(equalToConstant: Metrics.height)

        leadingStackCenterY = leadingButtonsStack.centerYAnchor.constraint(equalTo: centerYAnchor)
        trailingStackCenterY = trailingButtonsStack.centerYAnchor.constraint(equalTo: centerYAnchor)
        centerContainerCenterY = centerContainer.centerYAnchor.constraint(equalTo: centerYAnchor)

        NSLayoutConstraint.activate([
            heightConstraint,

            leadingButtonsStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.horizontalPadding),
            leadingStackCenterY,
            leadingButtonsStack.heightAnchor.constraint(equalToConstant: Metrics.buttonSize),

            trailingButtonsStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.horizontalPadding),
            trailingStackCenterY,
            trailingButtonsStack.heightAnchor.constraint(equalToConstant: Metrics.buttonSize),

            centerContainer.leadingAnchor.constraint(greaterThanOrEqualTo: leadingButtonsStack.trailingAnchor),
            centerContainer.trailingAnchor.constraint(lessThanOrEqualTo: trailingButtonsStack.leadingAnchor),
            centerContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
            centerContainerCenterY,

            titleLabel.leadingAnchor.constraint(equalTo: centerContainer.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: centerContainer.trailingAnchor),
            titleLabel.topAnchor.constraint(equalTo: centerContainer.topAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: centerContainer.bottomAnchor),
        ])
    }

    func setLeadingButtons(_ buttons: [UIView]) {
        removeButtonConstraints(from: leadingButtonsStack)
        leadingButtonsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        buttons.forEach {
            applyButtonConstraints(to: $0)
            leadingButtonsStack.addArrangedSubview($0)
        }
    }

    func setTrailingButtons(_ buttons: [UIView]) {
        removeButtonConstraints(from: trailingButtonsStack)
        trailingButtonsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        buttons.forEach {
            applyButtonConstraints(to: $0)
            trailingButtonsStack.addArrangedSubview($0)
        }
    }

    private func applyButtonConstraints(to view: UIView) {
        guard managedButtonConstraints[view] == nil else { return }
        // Only icon buttons should be forced to a square 44×44.
        guard isIconButton(view) else { return }
        let constraints = [
            view.widthAnchor.constraint(equalToConstant: Metrics.buttonSize),
            view.widthAnchor.constraint(equalTo: view.heightAnchor),
        ]
        NSLayoutConstraint.activate(constraints)
        managedButtonConstraints[view] = constraints
    }

    private func isIconButton(_ view: UIView) -> Bool {
        guard let button = view as? BrowserChromeButton else { return true }
        return button.hasImage && !button.hasTitle
    }

    private func removeButtonConstraints(from stack: UIStackView) {
        for view in stack.arrangedSubviews {
            if let constraints = managedButtonConstraints.removeValue(forKey: view) {
                NSLayoutConstraint.deactivate(constraints)
            }
        }
    }

    func updateForAddressBarPosition(isBottom: Bool) {
        let offset: CGFloat = isBottom ? Metrics.bottomBarVerticalOffset : 0
        leadingStackCenterY.constant = offset
        trailingStackCenterY.constant = offset
        centerContainerCenterY.constant = offset
    }

    func setCenterView(_ view: UIView?) {
        if let existing = currentCenterView {
            guard existing !== view else { return }
            existing.removeFromSuperview()
        }

        titleLabel.isHidden = view != nil

        if let view = view {
            centerContainer.addSubview(view)
            view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: centerContainer.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: centerContainer.trailingAnchor),
                view.topAnchor.constraint(equalTo: centerContainer.topAnchor),
                view.bottomAnchor.constraint(equalTo: centerContainer.bottomAnchor),
            ])
            currentCenterView = view
        } else {
            currentCenterView = nil
        }
    }
}
