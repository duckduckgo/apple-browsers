//
//  NewChatHintsView.swift
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

import AIChat
import UIKit

final class NewChatHintsView: UIView {

    enum Metrics {
        static let height: CGFloat = 36
        static let leadingInset: CGFloat = 16
        static let spacing: CGFloat = 8
        static let entranceOffset: CGFloat = 96
        static let entranceDuration: TimeInterval = 0.3
        static let entranceStagger: TimeInterval = 0.04
        static let entranceDamping: CGFloat = 0.7
        static let reducedMotionDuration: TimeInterval = 0.2
    }

    var onHintSelected: ((NewChatHint) -> Void)?

    private(set) var hints: [NewChatHint] = []

    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = false
        // Glass grows past a chip's bounds on touch, and its shadow sits outside them.
        scrollView.clipsToBounds = false
        scrollView.contentInset = UIEdgeInsets(top: 0, left: Metrics.leadingInset, bottom: 0, right: Metrics.leadingInset)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }()

    private let stackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = Metrics.spacing
        stackView.alignment = .center
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = false
        isHidden = true
        addSubview(scrollView)
        scrollView.addSubview(stackView)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Metrics.height),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Shows `hints` in order, or hides the row when empty. Coming into view, the chips slide in one after another;
    /// leaving is instant, so a hint never lingers over what the user is typing.
    func setHints(_ hints: [NewChatHint], animated: Bool) {
        if hints != self.hints {
            self.hints = hints
            rebuildChips()
        }
        let isShown = !hints.isEmpty
        guard isHidden == isShown else { return }
        isHidden = !isShown
        guard isShown else { return }
        scrollView.setContentOffset(CGPoint(x: -Metrics.leadingInset, y: 0), animated: false)
        if animated {
            animateEntrance()
        }
    }

    /// Taps between and beside the chips reach the page underneath.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        stackView.arrangedSubviews.contains { chip in
            chip.bounds.contains(chip.convert(point, from: self))
        }
    }

    private var chips: [AIChatQuickActionChipView] {
        stackView.arrangedSubviews.compactMap { $0 as? AIChatQuickActionChipView }
    }

    private func rebuildChips() {
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for hint in hints {
            let chip = AIChatQuickActionChipView()
            chip.backgroundStyle = .outlinedGlass
            chip.configure(with: NewChatHintAction(hint: hint))
            chip.onTap = { [weak self] in self?.onHintSelected?(hint) }
            stackView.addArrangedSubview(chip)
        }
    }

    private func animateEntrance() {
        let chips = chips
        let isReducedMotion = UIAccessibility.isReduceMotionEnabled
        let isRightToLeft = effectiveUserInterfaceLayoutDirection == .rightToLeft
        let offset = isRightToLeft ? -Metrics.entranceOffset : Metrics.entranceOffset
        UIView.performWithoutAnimation {
            layoutIfNeeded()
            for chip in chips {
                chip.layer.removeAllAnimations()
                chip.alpha = 0
                chip.transform = isReducedMotion ? .identity : CGAffineTransform(translationX: offset, y: 0)
            }
        }
        // Own timing: the row often appears inside the keyboard's animation.
        let options: UIView.AnimationOptions = [.allowUserInteraction, .beginFromCurrentState,
                                                .overrideInheritedDuration, .overrideInheritedCurve, .overrideInheritedOptions]
        for (index, chip) in chips.enumerated() {
            if isReducedMotion {
                UIView.animate(withDuration: Metrics.reducedMotionDuration, delay: 0, options: options) {
                    chip.alpha = 1
                }
                continue
            }
            UIView.animate(withDuration: Metrics.entranceDuration,
                           delay: Double(index) * Metrics.entranceStagger,
                           usingSpringWithDamping: Metrics.entranceDamping,
                           initialSpringVelocity: 0,
                           options: options) {
                chip.alpha = 1
                chip.transform = .identity
            }
        }
    }
}

private struct NewChatHintAction: AIChatQuickActionType {
    let hint: NewChatHint

    var id: String { "NewChatHint.\(hint.pixelValue)" }
    var title: String { hint.title }
    var prompt: String { "" }
    var icon: UIImage? { hint.icon }
}
