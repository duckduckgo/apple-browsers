//
//  MultiTabMentionSuggestionsView.swift
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
import DesignResourcesKit
import DesignResourcesKitIcons
import UIKit

/// Reuses contextual prompt chips without presenting a modal or taking the composer's focus.
final class MultiTabMentionSuggestionsView: UIView {
    private struct Action: AIChatQuickActionType {
        let suggestion: MultiTabMentionController.Suggestion

        var id: String { suggestion.candidate.tabId }
        var title: String { suggestion.candidate.title }
        var prompt: String { "" }
        var icon: UIImage? {
            suggestion.isSelected ? DesignSystemImages.Glyphs.Size16.checkCircle : DesignSystemImages.Glyphs.Size16.tabContent
        }
    }

    private enum Metrics {
        static let maximumVisibleRows = 3
        static let chipHeight: CGFloat = 36
        static let chipSpacing: CGFloat = 8
        static let scrollPadding: CGFloat = 4
    }

    var onSelect: ((MultiTabAttachmentCandidate) -> Void)?
    var onDismiss: (() -> Void)?

    private let actionsView = AIChatQuickActionsView<Action>()
    private let scrollView = UIScrollView()
    private let emptyLabel = UILabel()
    private var scrollHeightConstraint: NSLayoutConstraint!
    private var suggestions: [MultiTabMentionController.Suggestion]?

    init(usesGlassBackground: Bool) {
        super.init(frame: .zero)
        actionsView.chipBackgroundStyle = usesGlassBackground ? .glass : .translucent
        setupLayout()
        actionsView.onActionSelected = { [weak self] in self?.onSelect?($0.suggestion.candidate) }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with suggestions: [MultiTabMentionController.Suggestion]) {
        guard self.suggestions != suggestions else { return }
        self.suggestions = suggestions
        actionsView.configure(with: suggestions.map(Action.init),
                              isEnabled: { $0.suggestion.isEnabled },
                              isSelected: { $0.suggestion.isSelected })
        emptyLabel.isHidden = !suggestions.isEmpty
        actionsView.isHidden = suggestions.isEmpty
        let rows = CGFloat(max(1, min(suggestions.count, Metrics.maximumVisibleRows)))
        scrollHeightConstraint.constant = rows * Metrics.chipHeight + (rows - 1) * Metrics.chipSpacing + 2 * Metrics.scrollPadding
        scrollView.setContentOffset(.zero, animated: false)
    }

    override func accessibilityPerformEscape() -> Bool {
        onDismiss?()
        return true
    }

    private func setupLayout() {
        translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.text = UserText.aiChatChooseTabsNoMatches
        emptyLabel.font = .daxBodyRegular()
        emptyLabel.textColor = UIColor(designSystemColor: .textSecondary)
        emptyLabel.numberOfLines = 0
        scrollView.keyboardDismissMode = .none
        scrollView.showsVerticalScrollIndicator = true
        scrollView.delaysContentTouches = false

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        for child in [actionsView, emptyLabel] {
            child.translatesAutoresizingMaskIntoConstraints = false
            scrollView.addSubview(child)
        }

        scrollHeightConstraint = scrollView.heightAnchor.constraint(equalToConstant: Metrics.chipHeight)
        scrollHeightConstraint.priority = .defaultHigh
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 0),
            scrollHeightConstraint,
            actionsView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: Metrics.scrollPadding),
            actionsView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            actionsView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            actionsView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -Metrics.scrollPadding),
            actionsView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            emptyLabel.topAnchor.constraint(equalTo: scrollView.frameLayoutGuide.topAnchor, constant: Metrics.scrollPadding),
            emptyLabel.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor),
            emptyLabel.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor),
        ])
    }
}
