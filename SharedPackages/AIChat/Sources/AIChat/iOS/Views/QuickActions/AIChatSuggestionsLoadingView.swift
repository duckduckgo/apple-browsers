//
//  AIChatSuggestionsLoadingView.swift
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

#if os(iOS)
import DesignResourcesKit
import UIKit

// MARK: - View

/// A pill-shaped loading view shown in the suggested-prompts slot while suggestions resolve.
public final class AIChatSuggestionsLoadingView: UIView {
    // MARK: - Constants

    private enum Constants {
        static let height: CGFloat = 36
        static let cornerRadius: CGFloat = 12
        static let borderWidth: CGFloat = 1
        static let horizontalPadding: CGFloat = 14
        static let dotSize: CGFloat = 7
        static let dotSpacing: CGFloat = 5
        static let restingOpacity: Float = 0.3
        static let restingScale: CGFloat = 0.7
        static let animationDuration: CFTimeInterval = 1.0
        static let staggerDelay: CFTimeInterval = 0.2
        static let animationKey = "suggestionsLoadingPulse"
    }

    // MARK: - UI Components

    private let dotStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = Constants.dotSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var dots: [UIView] = (0..<3).map { _ in makeDot() }

    // MARK: - Initialization

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            startAnimating()
        } else {
            stopAnimating()
        }
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            layer.borderColor = UIColor(designSystemColor: .decorationQuaternary).cgColor
        }
    }

    // MARK: - Private

    private func setupUI() {
        backgroundColor = UIColor(designSystemColor: .controlsFillPrimary)
        layer.cornerRadius = Constants.cornerRadius
        layer.borderWidth = Constants.borderWidth
        layer.borderColor = UIColor(designSystemColor: .decorationQuaternary).cgColor

        dots.forEach { dotStack.addArrangedSubview($0) }
        addSubview(dotStack)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Constants.height),
            dotStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            dotStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Constants.horizontalPadding),
            dotStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Constants.horizontalPadding),
        ])
    }

    private func makeDot() -> UIView {
        let dot = UIView()
        dot.backgroundColor = UIColor(designSystemColor: .textSecondary)
        dot.layer.cornerRadius = Constants.dotSize / 2
        dot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: Constants.dotSize),
            dot.heightAnchor.constraint(equalToConstant: Constants.dotSize),
        ])
        return dot
    }

    // MARK: - Animation

    private func startAnimating() {
        guard !UIAccessibility.isReduceMotionEnabled else {
            applyStaticDots()
            return
        }

        let baseTime = CACurrentMediaTime()
        for (index, dot) in dots.enumerated() {
            dot.layer.removeAnimation(forKey: Constants.animationKey)
            dot.layer.add(makePulseAnimation(beginTime: baseTime + Double(index) * Constants.staggerDelay),
                          forKey: Constants.animationKey)
        }
    }

    private func stopAnimating() {
        dots.forEach { $0.layer.removeAnimation(forKey: Constants.animationKey) }
    }

    private func applyStaticDots() {
        dots.forEach {
            $0.layer.opacity = 1.0
            $0.layer.transform = CATransform3DIdentity
        }
    }

    private func makePulseAnimation(beginTime: CFTimeInterval) -> CAAnimationGroup {
        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [Constants.restingOpacity, 1.0, Constants.restingOpacity]
        opacity.keyTimes = [0, 0.5, 1]

        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = [Constants.restingScale, 1.0, Constants.restingScale]
        scale.keyTimes = [0, 0.5, 1]

        let group = CAAnimationGroup()
        group.animations = [opacity, scale]
        group.duration = Constants.animationDuration
        group.beginTime = beginTime
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        return group
    }
}
#endif
