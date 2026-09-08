//
//  MultiTabMentionMenuPresenter.swift
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

/// The token and attachment flow does not depend on the temporary system menu presentation.
@MainActor
protocol MultiTabMentionPresenting: AnyObject {
    func present(tabs: [MultiTabAttachmentCandidate],
                 attachedTabIds: Set<TabUID>,
                 sourceView: UIView,
                 sourceRect: CGRect,
                 onSelect: @escaping (MultiTabAttachmentCandidate) -> Void,
                 onDismiss: @escaping () -> Void)
    func dismiss()
}

@available(iOS 16.0, *)
@MainActor
final class MultiTabMentionMenuPresenter: NSObject, MultiTabMentionPresenting, UIEditMenuInteractionDelegate {
    private lazy var interaction = UIEditMenuInteraction(delegate: self)
    private weak var sourceView: UIView?
    private var sourceRect = CGRect.zero
    private var presentationId: UUID?
    private var tabs: [MultiTabAttachmentCandidate] = []
    private var attachedTabIds = Set<TabUID>()
    private var onSelect: ((MultiTabAttachmentCandidate) -> Void)?
    private var onDismiss: (() -> Void)?

    func present(tabs: [MultiTabAttachmentCandidate],
                 attachedTabIds: Set<TabUID>,
                 sourceView: UIView,
                 sourceRect: CGRect,
                 onSelect: @escaping (MultiTabAttachmentCandidate) -> Void,
                 onDismiss: @escaping () -> Void) {
        if self.sourceView !== sourceView {
            dismiss()
            self.sourceView = sourceView
            sourceView.addInteraction(interaction)
        }
        self.tabs = tabs
        self.attachedTabIds = attachedTabIds
        self.sourceRect = sourceRect
        self.onSelect = onSelect
        self.onDismiss = onDismiss
        if presentationId != nil {
            interaction.reloadVisibleMenu()
            interaction.updateVisibleMenuPosition(animated: false)
        } else {
            let id = UUID()
            presentationId = id
            interaction.presentEditMenu(with: UIEditMenuConfiguration(identifier: id as NSUUID,
                                                                      sourcePoint: CGPoint(x: sourceRect.midX, y: sourceRect.midY)))
        }
    }

    func dismiss() {
        presentationId = nil
        onSelect = nil
        onDismiss = nil
        interaction.dismissMenu()
        sourceView?.removeInteraction(interaction)
        sourceView = nil
    }

    func editMenuInteraction(_ interaction: UIEditMenuInteraction,
                             menuFor configuration: UIEditMenuConfiguration,
                             suggestedActions: [UIMenuElement]) -> UIMenu? {
        let actions = tabs.map { tab in
            let action = UIAction(title: tab.title, state: attachedTabIds.contains(tab.tabId) ? .on : .off) { [weak self] _ in
                self?.onSelect?(tab)
            }
            action.subtitle = tab.url.host
            return action
        }
        // Temporary copy for the local hack phase, alongside the temporary presenter.
        let children = actions.isEmpty ? [UIAction(title: "No matching tabs", attributes: .disabled) { _ in }] : actions
        return UIMenu(children: children)
    }

    func editMenuInteraction(_ interaction: UIEditMenuInteraction, targetRectFor configuration: UIEditMenuConfiguration) -> CGRect {
        sourceRect
    }

    func editMenuInteraction(_ interaction: UIEditMenuInteraction,
                             willDismissMenuFor configuration: UIEditMenuConfiguration,
                             animator: any UIEditMenuInteractionAnimating) {
        guard let presentationId, configuration.identifier as? UUID == presentationId else { return }
        self.presentationId = nil
        let onDismiss = onDismiss
        self.onSelect = nil
        self.onDismiss = nil
        onDismiss?()
    }
}
