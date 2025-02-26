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
import Combine

enum DefaultBrowserAndDockPromptPresentationType {
    case banner
    case popover
}

protocol DefaultBrowserAndDockPromptPresenting {
    var bannerDismissedPublisher: AnyPublisher<Void, Never> { get }

    func tryToShowPrompt(popoverAnchorProvider: () -> NSView?,
                         bannerViewHandler: (BannerMessageViewController) -> Void)
}

final class DefaultBrowserAndDockPromptPresenter: DefaultBrowserAndDockPromptPresenting {
    static let shared = DefaultBrowserAndDockPromptPresenter()

    private let coordinator: DefaultBrowserAndDockPrompt
    private let bannerDismissedSubject = PassthroughSubject<Void, Never>()

    private var popover: NSPopover?

    init(coordinator: DefaultBrowserAndDockPrompt = DefaultBrowserAndDockPromptCoordinator()) {
        self.coordinator = coordinator
    }

    var bannerDismissedPublisher: AnyPublisher<Void, Never> {
        bannerDismissedSubject.eraseToAnyPublisher()
    }

    func tryToShowPrompt(popoverAnchorProvider: () -> NSView?,
                         bannerViewHandler: (BannerMessageViewController) -> Void) {
        guard let type = coordinator.getPromptType() else {
            return
        }

        switch type {
        case .banner:
            guard let banner = getBanner() else { return }

            bannerViewHandler(banner)
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

    private func getBanner() -> BannerMessageViewController? {
        guard let type = coordinator.evaluatePromptEligibility else {
            return nil
        }

        let content = DefaultBrowserAndDockPromptContent.banner(type)

        return BannerMessageViewController(
            message: content.message,
            image: content.icon,
            buttonText: content.primaryButtonTitle,
            buttonAction: {
                self.coordinator.onPromptConfirmation()
                self.bannerDismissedSubject.send()
            },
            closeAction: {
                self.bannerDismissedSubject.send()
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
            buttonAction: {
                self.coordinator.onPromptConfirmation()
                self.popover?.close()
            },
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
