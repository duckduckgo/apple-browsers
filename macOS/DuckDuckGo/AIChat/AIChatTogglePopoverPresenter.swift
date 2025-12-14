//
//  AIChatTogglePopoverPresenter.swift
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

import Foundation
import AppKit

@MainActor
protocol AIChatTogglePopoverPresenting: AnyObject {
    func isPopoverBeingPresented() -> Bool
    func showPopover(viewController: PopoverMessageViewController, relativeTo toggleControl: NSView)
    func dismissPopover()
    func notifyPopoverDismissed()
}

@MainActor
final class AIChatTogglePopoverPresenter: AIChatTogglePopoverPresenting {

    private let windowControllersManager: WindowControllersManagerProtocol
    private weak var activePopover: PopoverMessageViewController?
    private var isPresentingPopover: Bool = false
    init(windowControllersManager: WindowControllersManagerProtocol) {
        self.windowControllersManager = windowControllersManager
    }

    func isPopoverBeingPresented() -> Bool {
        isPresentingPopover
    }

    func showPopover(viewController: PopoverMessageViewController, relativeTo toggleControl: NSView) {
        guard let mainWindowController = windowControllersManager.lastKeyMainWindowController else {
            return
        }

        activePopover = viewController
        isPresentingPopover = true

        viewController.show(onParent: mainWindowController.mainViewController,
                            relativeTo: toggleControl,
                            preferredEdge: .minY,
                            behavior: .applicationDefined)
    }

    func dismissPopover() {
        guard let popover = activePopover else {
            return
        }
        popover.dismiss(nil)
        activePopover = nil
    }

    func notifyPopoverDismissed() {
        activePopover = nil

        /// Give time for the popover animation to finish
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.isPresentingPopover = false
        }
    }
}
