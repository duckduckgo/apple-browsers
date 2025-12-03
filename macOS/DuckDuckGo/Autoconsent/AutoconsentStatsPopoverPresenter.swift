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

import Foundation
import AppKit
import AutoconsentStats
import PixelKit

@MainActor
protocol AutoconsentStatsPopoverPresenting: AnyObject {
    func isPopoverBeingPresented() -> Bool
    func showPopover(onClose: @escaping () -> Void,
                     onClick: @escaping () -> Void,
                     onAutoDismiss: (() -> Void)?) async
    func dismissPopover()
}

@MainActor
final class AutoconsentStatsPopoverPresenter: AutoconsentStatsPopoverPresenting {

    private enum Constants {
        static let autoDismissDuration: TimeInterval = 8.0
    }

    private let autoconsentStats: AutoconsentStatsCollecting
    private let windowControllersManager: WindowControllersManagerProtocol
    private weak var activePopover: PopoverMessageViewController?

    init(autoconsentStats: AutoconsentStatsCollecting,
         windowControllersManager: WindowControllersManagerProtocol) {
        self.autoconsentStats = autoconsentStats
        self.windowControllersManager = windowControllersManager
    }

    func isPopoverBeingPresented() -> Bool {
        activePopover != nil
    }

    func showPopover(onClose: @escaping () -> Void,
                     onClick: @escaping () -> Void,
                     onAutoDismiss: (() -> Void)? = nil) async {
        guard let mainWindowController = windowControllersManager.lastKeyMainWindowController else {
            return
        }

        let totalBlocked = await autoconsentStats.fetchTotalCookiePopUpsBlocked()
        let tabBarVC = mainWindowController.mainViewController.tabBarViewController

        let targetButton: NSView? = {
            @MainActor
            func findFooterButton(in view: NSView) -> NSButton? {
                if let tabBarFooter = view as? TabBarFooter {
                    return tabBarFooter.addButton
                }
                for subview in view.subviews {
                    if let button = findFooterButton(in: subview) {
                        return button
                    }
                }
                return nil
            }

            if let footerButton = findFooterButton(in: tabBarVC.view), !footerButton.isHidden {
                return footerButton
            } else if let addTabButton = tabBarVC.addTabButton, addTabButton.isHidden == false {
                return addTabButton
            } else {
                return nil
            }
        }()

        guard let button = targetButton else {
            return
        }

        let dialogImage: NSImage? = NSImage(named: "Cookies-Blocked-Color-24")

        let viewController = PopoverMessageViewController(
            title: UserText.autoconsentStatsPopoverTitle(count: Int(totalBlocked)),
            message: UserText.autoconsentStatsPopoverMessage,
            image: dialogImage,
            popoverStyle: .featureDiscovery,
            autoDismissDuration: Constants.autoDismissDuration,
            shouldShowCloseButton: true,
            clickAction: onClick,
            onClose: onClose,
            onAutoDismiss: onAutoDismiss
        )

        activePopover = viewController

        viewController.show(onParent: mainWindowController.mainViewController,
                            relativeTo: button,
                            behavior: .applicationDefined)

        PixelKit.fire(AutoconsentPixel.popoverShown, frequency: .daily)
    }

    func dismissPopover() {
        guard let popover = activePopover else {
            return
        }
        popover.dismiss(nil)
        activePopover = nil
    }
}
