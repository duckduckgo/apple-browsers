//
//  DefaultBrowserAndDockPresenter.swift
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

import SwiftUIExtensions

enum DefaultBrowserAndDockPromptPresentationType {
    case banner
    case popover
}

protocol DefaultBrowserAndDockPromptPresenting {
    func tryToShowPrompt(popoverAnchorProvider: () -> NSView?,
                         hideBanner: @escaping () -> Void,
                         bannerViewHandler: (BannerMessageViewController) -> Void)
}

final class DefaultBrowserAndDockPromptPresenter: DefaultBrowserAndDockPromptPresenting {
    static let shared = DefaultBrowserAndDockPromptPresenter()

    private let coordinator: DefaultBrowserAndDockPrompt

    private var popover: NSPopover?

    init(coordinator: DefaultBrowserAndDockPrompt = DefaultBrowserAndDockPromptCoordinator()) {
        self.coordinator = coordinator
    }

    func tryToShowPrompt(popoverAnchorProvider: () -> NSView?,
                         hideBanner: @escaping () -> Void,
                         bannerViewHandler: (BannerMessageViewController) -> Void) {
        guard let type = coordinator.tryToShowPrompt() else {
            return
        }

        switch type {
        case .banner:
            bannerViewHandler(getBanner(closeAction: hideBanner)!)
        case .popover:
            guard let view = popoverAnchorProvider() else { return }

            showPopover(below: view)
        }
    }

    // MARK: - Private

    private func showPopover(below view: NSView) {
        guard let content = coordinator.evaluatePromptEligibility else {
            return
        }

        if popover != nil {
            self.showPopover(positionedBelow: view)
        } else {
            self.initializePopover(with: content)
            self.showPopover(positionedBelow: view)
        }
    }

    private func getBanner(closeAction: @escaping (() -> Void)) -> BannerMessageViewController? {
        guard let type = coordinator.evaluatePromptEligibility else {
            return nil
        }

        let content = DefaultBrowserAndDockPromptContent.banner(type)

        return BannerMessageViewController(
            message: content.message,
            image: content.icon,
            buttonText: content.primaryButtonTitle,
            buttonAction: { self.coordinator.onPromptConfirmation() },
            closeAction: {
                closeAction()
                self.coordinator.onPromptDismissed()
            })
    }

    private func createPopover(with type: DefaultBrowserAndDockPromptType) -> NSHostingController<PopoverMessageView> {
        let content = DefaultBrowserAndDockPromptContent.popover(type)
        let viewModel = PopoverMessageViewModel(
            title: content.title,
            message: content.message,
            image: content.icon,
            buttonText: content.primaryButtonTitle,
            buttonAction: { self.coordinator.onPromptConfirmation() },
            secondaryButtonText: content.secondaryButtonTitle,
            secondaryButtonAction: {
                self.popover?.close()
                self.coordinator.onPromptDismissed()
            },
            shouldShowCloseButton: false,
            shouldPresentMultiline: true,
            alignment: .vertical)

        let contentView = PopoverMessageView(viewModel: viewModel, onClick: nil, onClose: nil)

        return NSHostingController(rootView: contentView)
    }

    private func initializePopover(with type: DefaultBrowserAndDockPromptType) {
        let viewController = createPopover(with: type)
        popover = DefaultBrowserAndDockPromptPopover(viewController: viewController)
    }

    private func showPopover(positionedBelow view: NSView) {
        popover?.show(positionedBelow: view)
        popover?.contentViewController?.view.makeMeFirstResponder()
    }
}
