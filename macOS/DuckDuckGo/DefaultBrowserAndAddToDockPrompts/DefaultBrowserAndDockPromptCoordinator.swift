//
//  DefaultBrowserAndDockPromptCoordinator.swift
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

protocol DefaultBrowserAndDockPrompt {
    var isUserEligibleForPrompt: Bool { get }

    func showPopover(below view: NSView)
    func getBanner(closeAction: @escaping (() -> Void)) -> BannerMessageViewController?
}

final class DefaultBrowserAndDockPromptCoordinator: DefaultBrowserAndDockPrompt {
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

    var isUserEligibleForPrompt: Bool {
        let wasOnboardingCompleted = true // TODO: Swap for real value
        return AppDelegate.twoDaysPassedSinceFirstLaunch && wasOnboardingCompleted
    }

    func showPopover(below view: NSView) {
        guard let content = evaluatePromptEligibility else {
            return
        }

        var popover: NSPopover?
        let style = DefaultBrowserAndDockPromptPresentation.popover(content)
        let viewModel = PopoverMessageViewModel(
            title: style.title,
            message: style.message,
            image: style.icon,
            buttonText: style.primaryButtonTitle,
            buttonAction: { self.onPromptConfirmation() },
            secondaryButtonText: style.secondaryButtonTitle,
            secondaryButtonAction: {
                popover?.close()
                self.onPromptDismissed()
            },
            shouldShowCloseButton: false,
            shouldPresentMultiline: true,
            alignment: .vertical)

        let contentView = PopoverMessageView(viewModel: viewModel, onClick: nil, onClose: nil)
        let viewController = NSHostingController(rootView: contentView)
        popover = DefaultBrowserAndDockPromptPopover(viewController: viewController)
        popover?.show(positionedBelow: view)
        popover?.contentViewController?.view.makeMeFirstResponder()
    }

    func getBanner(closeAction: @escaping (() -> Void)) -> BannerMessageViewController? {
        guard let content = evaluatePromptEligibility else {
            return nil
        }

        let style = DefaultBrowserAndDockPromptPresentation.banner(content)

        return BannerMessageViewController(
            message: style.message,
            image: style.icon,
            buttonText: style.primaryButtonTitle,
            buttonAction: { self.onPromptConfirmation() },
            closeAction: {
                closeAction()
                self.onPromptDismissed()
            })
    }

    // MARK: - Private

    /// Evaluates the user's eligibility for the default browser and dock prompt, and returns the appropriate
    /// `DefaultBrowserAndDockPromptContent` value based on the user's current state (default browser status, dock status, and whether it's a Sparkle build).
    ///
    /// The implementation checks the following conditions:
    /// - If this is a Sparkle build:
    ///   - If the user has both set DuckDuckGo as the default browser and added it to the dock, they are not eligible for any prompt (returns `nil`).
    ///   - If the user has set DuckDuckGo as the default browser but hasn't added it to the dock, it returns `.addToDockPrompt`.
    ///   - If the user hasn't set DuckDuckGo as the default browser but has added it to the dock, it returns `.setAsDefaultPrompt`.
    ///   - If the user hasn't set DuckDuckGo as the default browser and hasn't added it to the dock, it returns `.bothDefaultBrowserAndDockPrompt`.
    /// - If this is not a Sparkle build, it only returns `.setAsDefaultPrompt` if the user hasn't already set DuckDuckGo as the default browser (otherwise, it returns `nil`).
    ///
    /// - Returns: The appropriate `DefaultBrowserAndDockPromptContent` value, or `nil` if the user is not eligible for any prompt.
    private var evaluatePromptEligibility: DefaultBrowserAndDockPromptContent? {
        let isDefaultBrowser = defaultBrowserProvider.isDefault
        let isAddedToDock = dockCustomization.isAddedToDock

        if isSparkleBuild {
            if isDefaultBrowser && isAddedToDock {
                return nil
            } else if isDefaultBrowser && !isAddedToDock {
                return .addToDockPrompt
            } else if !isDefaultBrowser && isAddedToDock {
                return .setAsDefaultPrompt
            } else {
                return .bothDefaultBrowserAndDockPrompt
            }
        } else {
            return isDefaultBrowser ? nil : .setAsDefaultPrompt
        }
    }

    private func onPromptConfirmation() {
        if isSparkleBuild && !dockCustomization.isAddedToDock {
            dockCustomization.addToDock()
        }

        do {
            try defaultBrowserProvider.presentDefaultBrowserPrompt()
        } catch {
            defaultBrowserProvider.openSystemPreferences()
        }
    }

    private func onPromptDismissed() {
        /// TODO: We need to do the following:
        /// - Fire a pixel with the dimissal (the experiment one)
        /// - Save a flag in user defaults so we do not show the popover again
    }
}
