//
//  AIChatTogglePopoverCoordinator.swift
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
import SwiftUI
import DesignResourcesKit
import DesignResourcesKitIcons

@MainActor
protocol AIChatTogglePopoverCoordinating: AnyObject {
    func showPopoverIfNeeded(relativeTo toggleControl: NSView)
    func dismissPopover()
    func showPopoverForDebug(relativeTo toggleControl: NSView)
    func clearPopoverSeenFlag()
}

@MainActor
final class AIChatTogglePopoverCoordinator: AIChatTogglePopoverCoordinating {

    private let windowControllersManager: WindowControllersManagerProtocol
    private let themeManager: ThemeManaging
    private let presenter: AIChatTogglePopoverPresenting

    private enum StorageKey {
        static let popoverSeen = "aichat.toggle.popover.seen"
    }

    private enum Constants {
        static let autoDismissDuration: TimeInterval = 8.0
    }

    init(windowControllersManager: WindowControllersManagerProtocol,
         themeManager: ThemeManaging? = nil,
         presenter: AIChatTogglePopoverPresenting? = nil) {
        self.windowControllersManager = windowControllersManager
        self.themeManager = themeManager ?? NSApp.delegateTyped.themeManager
        self.presenter = presenter ?? AIChatTogglePopoverPresenter(
            windowControllersManager: windowControllersManager
        )
    }

    func showPopoverIfNeeded(relativeTo toggleControl: NSView) {
        guard
            !presenter.isPopoverBeingPresented(),
            !hasBeenPresented()
        else {
            return
        }

        showPopover(relativeTo: toggleControl)
    }

    // MARK: - Private Methods

    private func hasBeenPresented() -> Bool {
        return UserDefaults.standard.bool(forKey: StorageKey.popoverSeen)
    }

    private func markPopoverAsSeen() {
        UserDefaults.standard.set(true, forKey: StorageKey.popoverSeen)
    }

    private func showPopover(relativeTo toggleControl: NSView) {
        let onClose: () -> Void = { [weak self] in
            self?.markPopoverAsSeen()
        }

        let onButtonAction: () -> Void = { [weak self] in
            self?.openAIChatSettings()
            self?.markPopoverAsSeen()
        }

        let onAutoDismiss: () -> Void = { [weak self] in
            self?.markPopoverAsSeen()
        }

        let dialogImage = DesignSystemImages.Color.Size96.announcement
        let accentColor = Color(themeManager.theme.colorsProvider.accentPrimaryColor)
        let configuration = PopoverConfiguration(
            style: .featureDiscovery,
            buttonLayout: .vertical,
            imageSize: CGSize(width: 76, height: 76),
            buttonStyle: .link,
            accentColor: accentColor
        )
        let viewController = PopoverMessageViewController(
            title: UserText.aiChatTogglePopoverTitle,
            message: UserText.aiChatTogglePopoverMessage,
            image: dialogImage,
            configuration: configuration,
            autoDismissDuration: Constants.autoDismissDuration,
            shouldShowCloseButton: true,
            presentMultiline: true,
            buttonText: UserText.aiChatTogglePopoverButton,
            buttonAction: onButtonAction,
            onClose: onClose,
            onAutoDismiss: onAutoDismiss
        )

        presenter.showPopover(viewController: viewController, relativeTo: toggleControl)
    }

    private func openAIChatSettings() {
        windowControllersManager.showTab(with: .settings(pane: .aiChat))
    }

    func dismissPopover() {
        guard presenter.isPopoverBeingPresented() else {
            return
        }
        presenter.dismissPopover()
    }

    // MARK: - Debug

    func showPopoverForDebug(relativeTo toggleControl: NSView) {
        guard !presenter.isPopoverBeingPresented() else {
            return
        }

        showPopover(relativeTo: toggleControl)
    }

    func clearPopoverSeenFlag() {
        UserDefaults.standard.removeObject(forKey: StorageKey.popoverSeen)
    }
}
