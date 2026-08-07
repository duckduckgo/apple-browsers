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
            chipView.configure(with: action)
            chipView.onTap = { [weak self] in
                self?.onActionSelected?(action)
            }
            stackView.addArrangedSubview(chipView)
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
