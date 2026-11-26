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
@MainActor
final class NewChatHintsPresenter {

    enum Metrics {
        static let cardSpacing: CGFloat = 10
    }

    /// Tab swipes move it with the input.
    let row = NewChatHintsView()
    private var cancellable: AnyCancellable?

    /// `swipeOverlay` covers the screen with sliding snapshots during a tab swipe; the row goes under it like the rest
    /// of the tab, so the chips slide away in the snapshot instead of staying on top.
    init(coordinator: UnifiedToggleInputCoordinator, parentView: UIView, swipeOverlay: UIView?) {
        row.translatesAutoresizingMaskIntoConstraints = false
        row.accessibilityIdentifier = "NewChatHints"
        if let swipeOverlay, swipeOverlay.superview === parentView {
            parentView.insertSubview(row, belowSubview: swipeOverlay)
        } else {
            parentView.addSubview(row)
        }
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: parentView.safeAreaLayoutGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: parentView.safeAreaLayoutGuide.trailingAnchor),
            row.bottomAnchor.constraint(equalTo: coordinator.viewController.inputCardTopAnchor, constant: -Metrics.cardSpacing),
        ])
        row.onHintSelected = { [weak coordinator] in coordinator?.performNewChatHint($0) }
        cancellable = coordinator.$newChatHints.sink { [weak self, weak coordinator] hints in
            self?.row.setHints(hints, animated: true)
            if !hints.isEmpty {
                coordinator?.newChatHintsDidAppear(hints)
            }
        }
    }
}
