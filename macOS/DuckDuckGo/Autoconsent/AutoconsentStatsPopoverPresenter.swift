//
//  AutoconsentStatsPopoverPresenter.swift
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

import AppKit
import Combine
import Foundation

@MainActor
protocol AutoconsentStatsPopoverPresenting: AnyObject {
    func isPopoverBeingPresented() -> Bool
    /// Returns `false` if there was no window/anchor to present against, so callers can resolve
    /// their own pending state instead of leaving it hanging on a promo that never actually appeared.
    @discardableResult
    func showPopover(viewController: PopoverMessageViewController, onAnchorHidden: @escaping () -> Void) -> Bool
    func dismissPopover()
}

@MainActor
final class AutoconsentStatsPopoverPresenter: AutoconsentStatsPopoverPresenting {

    private let windowControllersManager: WindowControllersManagerProtocol
    private weak var activePopover: PopoverMessageViewController?
    private var anchorVisibilityCancellable: AnyCancellable?

    init(windowControllersManager: WindowControllersManagerProtocol) {
        self.windowControllersManager = windowControllersManager
    }

    func isPopoverBeingPresented() -> Bool {
        activePopover != nil
    }

    @discardableResult
    func showPopover(viewController: PopoverMessageViewController, onAnchorHidden: @escaping () -> Void) -> Bool {
        guard let mainWindowController = windowControllersManager.lastKeyMainWindowController else {
            return false
        }

        let mainViewController = mainWindowController.mainViewController
        let tabBar = mainViewController.tabBarViewController
        let anchor: NSView
        let preferredEdge: NSRectEdge
        var anchorHidden = tabBar.$isTabStripHidden
            .removeDuplicates()
            .dropFirst()
            .map { _ in () }
            .eraseToAnyPublisher()

        if let sidebar = mainViewController.verticalTabsSidebarPresenter {
            guard let button = sidebar.dockedNewTabButtonAnchor, button.isVisible, !button.visibleRect.isEmpty else { return false }
            anchor = button
            preferredEdge = .maxX
            let sidebarUndocked = sidebar.$layout.filter { $0 != .docked }.map { _ in () }
            anchorHidden = anchorHidden.merge(with: sidebarUndocked).eraseToAnyPublisher()
        } else {
            guard let button = tabBar.visibleNewTabButton else { return false }
            anchor = button
            preferredEdge = .maxY
        }

        activePopover = viewController
        anchorVisibilityCancellable = anchorHidden.first().sink { [weak self, weak viewController] in
            guard let viewController, self?.activePopover === viewController else { return }
            onAnchorHidden()
        }

        viewController.show(onParent: mainViewController, relativeTo: anchor, preferredEdge: preferredEdge, behavior: .applicationDefined)
        return true
    }

    func dismissPopover() {
        anchorVisibilityCancellable = nil
        guard let popover = activePopover else {
            return
        }
        popover.dismiss(nil)
        activePopover = nil
    }
}
