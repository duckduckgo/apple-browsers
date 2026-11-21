//
//  NewChatHintsPresenter.swift
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

import Combine
import UIKit

/// Puts the coordinator's new chat hints above the full-tab Duck.ai input card, moving with it as the keyboard does.
/// Until the page and the row can share the empty chat's space, the row stays hidden whenever the page's empty-chat
/// content would not fit above it.
@MainActor
final class NewChatHintsPresenter {

    enum Metrics {
        static let cardSpacing: CGFloat = 10
        /// Room the page needs between the chat header and the row for its empty-chat logo and privacy line, which it
        /// centres in the space above the input.
        static let minimumPageHeight: CGFloat = 230
    }

    private weak var coordinator: UnifiedToggleInputCoordinator?
    private weak var parentView: UIView?
    private weak var headerView: UIView?
    private let row = NewChatHintsView()
    private var hints: [NewChatHint] = []
    private var cancellable: AnyCancellable?

    init(coordinator: UnifiedToggleInputCoordinator, parentView: UIView, headerView: UIView?, below inputContainer: UIView) {
        self.coordinator = coordinator
        self.parentView = parentView
        self.headerView = headerView
        row.translatesAutoresizingMaskIntoConstraints = false
        row.accessibilityIdentifier = "NewChatHints"
        if inputContainer.superview === parentView {
            parentView.insertSubview(row, belowSubview: inputContainer)
        } else {
            parentView.addSubview(row)
        }
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: parentView.safeAreaLayoutGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: parentView.safeAreaLayoutGuide.trailingAnchor),
            row.bottomAnchor.constraint(equalTo: coordinator.viewController.inputCardTopAnchor, constant: -Metrics.cardSpacing),
        ])
        row.onHintSelected = { [weak coordinator] in coordinator?.performNewChatHint($0) }
        cancellable = coordinator.$newChatHints.sink { [weak self] hints in
            self?.hints = hints
            self?.updateLayout()
        }
    }

    /// Call on every layout pass: the room above the card changes with the keyboard.
    func updateLayout() {
        let shown = hasRoom ? hints : []
        guard shown != row.hints || row.isHidden == !shown.isEmpty else { return }
        row.setHints(shown, animated: true)
        if !shown.isEmpty {
            coordinator?.newChatHintsDidAppear(shown)
        }
    }

    private var hasRoom: Bool {
        guard !hints.isEmpty, let coordinator, let parentView else { return false }
        let card = coordinator.viewController.inputCardFrame(in: parentView)
        guard !card.isEmpty else { return false }
        let top: CGFloat
        if let headerView, headerView.window != nil, !headerView.isHidden {
            top = headerView.convert(headerView.bounds, to: parentView).maxY
        } else {
            top = parentView.safeAreaLayoutGuide.layoutFrame.minY
        }
        let rowTop = card.minY - Metrics.cardSpacing - NewChatHintsView.Metrics.height
        return rowTop - top >= Metrics.minimumPageHeight
    }
}
