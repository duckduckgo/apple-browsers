//
//  AIChatQuickActionsView.swift
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

#if os(iOS)
import UIKit

// MARK: - Constants

private enum AIChatQuickActionsViewConstants {
    static let chipSpacing: CGFloat = 8

    /// No head start needed: the loader fading out already separates the deck from the bar's arrival.
    static let entranceDelay: TimeInterval = 0
    /// The stacked deck fades in as one, so no single card reads as more important.
    static let deckRevealDuration: TimeInterval = 0.12
    static let deckScale: CGFloat = 0.94
    static let spreadDuration: TimeInterval = 0.45
    static let spreadStagger: TimeInterval = 0.04
    static let spreadDamping: CGFloat = 0.78
    static let spreadInitialVelocity: CGFloat = 0.15
    /// The loader dissolves before the deck arrives, so the two read as a handover.
    static let loaderFadeDuration: TimeInterval = 0.12
}

// MARK: - View

/// A vertically stacked container view for quick action chips.
public final class AIChatQuickActionsView<Action: AIChatQuickActionType>: UIView {

    // MARK: - Properties

    public var onActionSelected: ((Action) -> Void)?

    /// Applied to every chip. Use `.opaque` when the chips float over dimmed content.
    public var chipBackgroundStyle: AIChatQuickActionChipView.BackgroundStyle = .translucent {
        didSet {
            stackView.arrangedSubviews
                .compactMap { $0 as? AIChatQuickActionChipView }
                .forEach { $0.backgroundStyle = chipBackgroundStyle }
        }
    }

    private var loadingView: AIChatSuggestionsLoadingView?

    // MARK: - UI Components

    private lazy var stackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = AIChatQuickActionsViewConstants.chipSpacing
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    // MARK: - Initialization

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Configuration

    public func configure(with actions: [Action]) {
        stackView.arrangedSubviews
            .filter { $0 !== loadingView }
            .forEach {
                stackView.removeArrangedSubview($0)
                $0.removeFromSuperview()
            }

        for action in actions {
            let chipView = AIChatQuickActionChipView()
            chipView.backgroundStyle = chipBackgroundStyle
            chipView.configure(with: action)
            chipView.onTap = { [weak self] in
                self?.onActionSelected?(action)
            }
            stackView.addArrangedSubview(chipView)
        }
    }

    public var chipCount: Int {
        chips.count
    }

    /// The chips arrive as a deck: stacked on one spot, revealed together, then springing apart into
    /// their slots. Revealing them as a group avoids any one card looking more important than the rest.
    ///
    /// Requires a layout pass first: the deck position and each card's travel come from resting frames.
    public func animateChipsIn() {
        // Hidden up front: `configure` has already added them at full alpha, and anything that delays
        // the entrance would otherwise leave them on screen until it hides them again.
        chips.forEach { $0.alpha = 0 }

        // The loader holds a slot in the stack, so it fades and is removed before the cards are
        // measured — otherwise they would settle low and jump when it disappears.
        guard let loadingView else {
            runDeckEntrance()
            return
        }

        UIView.animate(withDuration: AIChatQuickActionsViewConstants.loaderFadeDuration,
                       delay: 0,
                       options: [.curveEaseOut, .beginFromCurrentState],
                       animations: {
            loadingView.alpha = 0
        }, completion: { [weak self] _ in
            guard let self else { return }
            self.setLoading(false)
            self.runDeckEntrance()
        })
    }

    private func runDeckEntrance() {
        layoutIfNeeded()
        let cards = chips
        cards.forEach { $0.transform = .identity }
        let restingTops = cards.map(\.frame.minY)
        guard let deckTop = restingTops.last else { return }

        for (card, restingTop) in zip(cards, restingTops) {
            card.alpha = 0
            card.transform = CGAffineTransform(translationX: 0, y: deckTop - restingTop)
                .scaledBy(x: AIChatQuickActionsViewConstants.deckScale,
                          y: AIChatQuickActionsViewConstants.deckScale)
        }

        // A stack view draws its last arranged subview on top, which would face the last card at the
        // viewer. Flip the z-order so the deck is dealt from the first card down.
        cards.reversed().forEach(stackView.bringSubviewToFront)

        UIView.animate(withDuration: AIChatQuickActionsViewConstants.deckRevealDuration,
                       delay: AIChatQuickActionsViewConstants.entranceDelay,
                       options: [.curveEaseOut, .beginFromCurrentState]) {
            cards.forEach { $0.alpha = 1 }
        }

        let spreadStart = AIChatQuickActionsViewConstants.entranceDelay
            + AIChatQuickActionsViewConstants.deckRevealDuration

        for (index, card) in cards.reversed().enumerated() {
            UIView.animate(withDuration: AIChatQuickActionsViewConstants.spreadDuration,
                           delay: spreadStart + Double(index) * AIChatQuickActionsViewConstants.spreadStagger,
                           usingSpringWithDamping: AIChatQuickActionsViewConstants.spreadDamping,
                           initialSpringVelocity: AIChatQuickActionsViewConstants.spreadInitialVelocity,
                           options: [.beginFromCurrentState]) {
                card.transform = .identity
            }
        }
    }

    private var chips: [UIView] {
        stackView.arrangedSubviews.filter { $0 !== loadingView }
    }

    /// Whether `point`, expressed in `view`'s coordinate space, lands on an actual chip.
    ///
    /// Lets a host treat the gaps around the chips as empty space rather than as part of this view.
    public func containsChip(at point: CGPoint, from view: UIView) -> Bool {
        stackView.arrangedSubviews.contains { chip in
            guard !chip.isHidden, chip.alpha > 0.01 else { return false }
            return chip.bounds.contains(view.convert(point, to: chip))
        }
    }

    public func setLoading(_ isLoading: Bool) {
        if isLoading {
            guard loadingView == nil else { return }
            let view = AIChatSuggestionsLoadingView()
            loadingView = view
            stackView.insertArrangedSubview(view, at: 0)
        } else {
            loadingView?.removeFromSuperview()
            loadingView = nil
        }
    }
}

// MARK: - Private Setup

private extension AIChatQuickActionsView {

    func setupUI() {
        isAccessibilityElement = false
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
        ])
    }
}
#endif
