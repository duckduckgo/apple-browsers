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

    /// Swaps the loader out for the chips, which are already in the stack behind it.
    public func showChips() {
        setLoading(false)
    }

    private var chips: [UIView] {
        stackView.arrangedSubviews.filter { $0 !== loadingView }
    }

    /// Whether `point`, in `view`'s coordinate space, lands on a chip rather than the gaps around them.
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
        let stackHost = installGlassContainerIfAvailable() ?? self
        stackHost.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(greaterThanOrEqualTo: stackHost.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: stackHost.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: stackHost.leadingAnchor),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: stackHost.trailingAnchor),
        ])
    }

    /// Renders every chip's glass as one combined effect rather than each resolving its own backdrop.
    /// Returns the view the stack should live in, or nil where the container effect is unavailable.
    func installGlassContainerIfAvailable() -> UIView? {
        guard #available(iOS 26.0, *) else { return nil }

        let containerEffect = UIGlassContainerEffect()
        // Below the chip spacing, so combining their rendering does not also merge them into one pill.
        containerEffect.spacing = 0
        let containerView = UIVisualEffectView(effect: containerEffect)
        containerView.translatesAutoresizingMaskIntoConstraints = false
        // Interactive glass scales a chip past its bounds on touch.
        containerView.clipsToBounds = false
        addSubview(containerView)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        return containerView.contentView
    }
}
#endif
