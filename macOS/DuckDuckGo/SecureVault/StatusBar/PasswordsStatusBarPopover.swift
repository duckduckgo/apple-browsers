//
//  PasswordsStatusBarPopover.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import BrowserServicesKit
import Combine

final class PasswordsStatusBarPopover: NSPopover {

    let themeManager: ThemeManaging = NSApp.delegateTyped.themeManager
    var themeUpdateCancellable: AnyCancellable?
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?
    private let pinningManager: PinningManager
    private weak var positioningButton: NSView?

    init(pinningManager: PinningManager, positioningButton: NSView?) {
        self.pinningManager = pinningManager
        self.positioningButton = positioningButton
        super.init()

        self.animates = false
        // Use applicationDefined to prevent auto-dismiss during TouchID authentication
        self.behavior = .applicationDefined
        self.delegate = self

        setupContentController()
        setupClickOutsideMonitor()

        subscribeToThemeChanges()
        applyThemeStyle()
    }

    required init?(coder: NSCoder) {
        fatalError("\(Self.self): Bad initializer")
    }

    deinit {
        removeClickMonitors()
#if DEBUG
        contentViewController?.ensureObjectDeallocated(after: 1.0, do: .interrupt)
#endif
    }

    // swiftlint:disable force_cast
    var viewController: PasswordManagementViewController { contentViewController as! PasswordManagementViewController }
    // swiftlint:enable force_cast

    /// Whether the popover can be safely dismissed (no authentication in progress and not editing).
    var canDismiss: Bool {
        !DeviceAuthenticator.shared.requiresAuthentication &&
        !DeviceAuthenticator.shared.isAuthenticating &&
        !viewController.isEditing
    }

    func select(category: SecureVaultSorting.Category?) {
        viewController.select(category: category)
    }

    private func setupContentController() {
        let controller = PasswordManagementViewController.create(pinningManager: pinningManager)
        contentViewController = controller
    }

    private func setupClickOutsideMonitor() {
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, self.isShown, self.canDismiss else { return }
            self.close()
        }

        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, self.isShown, self.canDismiss else { return event }
            let popoverWindow = self.contentViewController?.view.window
            let statusBarButtonWindow = self.positioningButton?.window
            if event.window !== popoverWindow && event.window !== statusBarButtonWindow {
                self.close()
            }
            return event
        }
    }

    private func removeClickMonitors() {
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalClickMonitor = nil
        }
        if let monitor = localClickMonitor {
            NSEvent.removeMonitor(monitor)
            localClickMonitor = nil
        }
    }
}

extension PasswordsStatusBarPopover: ThemeUpdateListening {

    func applyThemeStyle(theme: ThemeStyleProviding) {
        backgroundColor = theme.colorsProvider.popoverBackgroundColor
    }
}

extension PasswordsStatusBarPopover: NSPopoverDelegate {

    func popoverDidClose(_ notification: Notification) {
        removeClickMonitors()

        if let window = viewController.view.window {
            for sheet in window.sheets {
                window.endSheet(sheet)
            }
        }
        viewController.postChange()
        if !viewController.isDirty {
            viewController.clear()
        }
    }

    @MainActor func popoverShouldClose(_ popover: NSPopover) -> Bool {
        canDismiss
    }
}
