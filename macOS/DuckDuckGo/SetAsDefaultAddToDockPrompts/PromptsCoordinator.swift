//
//  PromptsCoordinator.swift
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

import SwiftUI
import SwiftUIExtensions

/// The `PromptsCoordinator` class is responsible for managing the display of prompts to the user in a macOS browser application.
///
/// This class serves as a centralized coordinator for handling different types of prompts, such as "Set As Default Browser" and "Add To The Dock". The decision on which prompt to display is based on a flag, which can be set to either show a popover or a banner.
///
/// The `PromptsCoordinator` class is designed to encapsulate the logic for determining which prompt to display, as well as the presentation of the prompt itself. This allows the rest of the application to interact with the `PromptsCoordinator` without needing to know the specific implementation details of each prompt type.
///
/// By using a coordinator pattern, the `PromptsCoordinator` class helps to maintain a separation of concerns and improve the overall organization and maintainability of the application's codebase. It also makes it easier to add or modify prompt types in the future, as the changes can be localized within the `PromptsCoordinator` class.
///
/// The `PromptsCoordinator` class should be responsible for the following tasks:
/// - Determining which prompt to display based on the provided flag
/// - Presenting the appropriate prompt (popover or banner) to the user
/// - Handling user interactions with the prompt (e.g., setting the browser as default, adding to the dock)
/// - Providing a consistent interface for other parts of the application to interact with the prompts
/// - Firing pixels related to the prompts
///
/// By encapsulating the prompt-related logic within the `PromptsCoordinator` class, the rest of the application can focus on its core functionality, while the `PromptsCoordinator` ensures that the prompts are displayed and handled correctly.
final class PromptsCoordinator {
    let dockCustomization: DockCustomization
    let defaultBrowserProvider: DefaultBrowserProvider
#if SPARKLE
    let isSparkleBuild: Bool = true
#else
    let isSparkleBuild: Bool = false
#endif

    init(dockCustomization: DockCustomization = DockCustomizer(),
         defaultBrowserProvider: DefaultBrowserProvider = SystemDefaultBrowserProvider()) {
        self.dockCustomization = dockCustomization
        self.defaultBrowserProvider = defaultBrowserProvider
    }

    var shouldShowPrompt: Bool {
        let wasOnboardingCompleted = false // TODO: Swap for real value
//        return AppDelegate.twoDaysPassedSinceFirstLaunch && wasOnboardingCompleted
        return true
    }

    func showPopover(below view: NSView) {
        let isDefaultBrowser = defaultBrowserProvider.isDefault
        let isAddedToDock = dockCustomization.isAddedToDock
        guard let content = PromptContent.getStyle(isSparkle: isSparkleBuild, isDefaultBrowser: isDefaultBrowser, isOnDock: isAddedToDock) else {
            return
        }
        var popover: NSPopover?
        let style = PromptStyle.popover(content)
        let viewModel = PopoverMessageViewModel(title: style.title,
                                                message: style.message,
                                                image: style.icon,
                                                buttonText: style.primaryButtonTitle,
                                                buttonAction: { self.onSetAsDefaultBrowser() },
                                                secondaryButtonText: style.secondaryButtonTitle,
                                                secondaryButtonAction: { popover?.close() },
                                                shouldShowCloseButton: false,
                                                shouldPresentMultiline: true,
                                                alignment: .vertical)
        let contentView = PopoverMessageView(viewModel: viewModel, onClick: nil, onClose: nil)
        let viewController = NSHostingController(rootView: contentView)
        popover = CenteredPromptPopover(viewController: viewController)
        popover?.show(positionedBelow: view)
        popover?.contentViewController?.view.makeMeFirstResponder()
    }

    // MARK: - Private

    private func onSetAsDefaultBrowser() {
        if isSparkleBuild && !dockCustomization.isAddedToDock{
            dockCustomization.addToDock()
        }

        do {
            try defaultBrowserProvider.presentDefaultBrowserPrompt()
        } catch {
            defaultBrowserProvider.openSystemPreferences()
        }
    }

    private func onPopoverDismissed() {
        /// TODO: We need to do the following:
        /// - Fire a pixel with the dimissal
        /// - Save a flag in user defaults so we do not show the popover again
    }
}
