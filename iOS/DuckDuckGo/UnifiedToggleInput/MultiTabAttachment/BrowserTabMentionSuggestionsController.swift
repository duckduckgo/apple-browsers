//
//  BrowserTabMentionSuggestionsController.swift
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

/// Presents mentions in the free space next to the browser's input, independent of its bar position.
@MainActor
final class BrowserTabMentionSuggestionsController {
    private weak var coordinator: UnifiedToggleInputCoordinator?
    private weak var parentView: UIView?
    private weak var suppressedContentView: UIView?
    private var wasContentHidden = false
    private var suggestionsView: MultiTabMentionSuggestionsView?

    init(coordinator: UnifiedToggleInputCoordinator, parentView: UIView) {
        self.coordinator = coordinator
        self.parentView = parentView
    }

    func show(_ suggestions: [MultiTabMentionController.Suggestion]?) {
        guard let suggestions, !suggestions.isEmpty, let coordinator, let parentView else {
            dismiss()
            return
        }

        if suggestionsView == nil {
            let panel = MultiTabMentionSuggestionsView(showsGlassShadow: true)
            panel.translatesAutoresizingMaskIntoConstraints = true
            panel.onSelect = { [weak coordinator] in coordinator?.selectTabMention($0) }
            panel.onDismiss = { [weak coordinator] in coordinator?.dismissTabMentions() }
            parentView.addSubview(panel)
            suggestionsView = panel
        }
        suggestionsView?.overrideUserInterfaceStyle = coordinator.viewController.handler.isFireTab ? .dark : .unspecified
        suggestionsView?.configure(with: suggestions)
        updateLayout()
    }

    func updateLayout() {
        guard let panel = suggestionsView, let coordinator, let parentView else { return }
        let card = coordinator.viewController.inputCardFrame(in: parentView)
        let safeFrame = parentView.safeAreaLayoutGuide.layoutFrame
        let keyboardTop = parentView.keyboardLayoutGuide.layoutFrame.minY
        let gap: CGFloat = 8
        let availableBottom = min(safeFrame.maxY, keyboardTop - gap)
        let showsAbove = coordinator.viewController.cardPosition == .bottom
        let topBoundary: CGFloat
        let bottomBoundary: CGFloat
        if showsAbove {
            topBoundary = safeFrame.minY
            bottomBoundary = min(card.minY - gap, availableBottom)
        } else {
            topBoundary = max(card.maxY + gap, safeFrame.minY)
            bottomBoundary = availableBottom
        }
        let availableHeight = max(0, bottomBoundary - topBoundary)
        let width = min(card.width, safeFrame.width)
        let hasRoomForSuggestion = width > 0 && availableHeight >= panel.minimumVisibleHeight
        panel.isHidden = !hasRoomForSuggestion
        setContentSuppressed(hasRoomForSuggestion)
        guard hasRoomForSuggestion else { return }

        let height = min(panel.preferredContentHeight, availableHeight)
        let frame = CGRect(x: max(safeFrame.minX, min(card.minX, safeFrame.maxX - width)),
                           y: showsAbove ? bottomBoundary - height : topBoundary,
                           width: width, height: height)
        if panel.frame != frame {
            panel.frame = frame
        }
        panel.layoutIfNeeded()
        parentView.bringSubviewToFront(panel)
    }

    func dismiss() {
        suggestionsView?.dismiss()
        suggestionsView = nil
        setContentSuppressed(false)
    }

    private func setContentSuppressed(_ suppressed: Bool) {
        if suppressed {
            guard suppressedContentView == nil, let contentView = coordinator?.contentViewController.view else { return }
            // Browser chrome owns the container's visibility. Suppress only its content child,
            // so render-state updates remain authoritative while a mention is being edited.
            suppressedContentView = contentView
            wasContentHidden = contentView.isHidden
            contentView.isHidden = true
        } else {
            suppressedContentView?.isHidden = wasContentHidden
            suppressedContentView = nil
        }
    }
}
