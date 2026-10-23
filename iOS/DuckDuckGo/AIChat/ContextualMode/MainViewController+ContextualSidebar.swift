//
//  MainViewController+ContextualSidebar.swift
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

extension MainViewController: AIChatContextualSidebarHosting {

    /// The iPad layout with the tabs bar, in a window wide enough to leave the page a phone's width beside it.
    /// Reads the width the window is resizing to, so a rotation can be judged before it lands.
    var canPresentContextualSidebar: Bool {
        typealias Constants = MainViewCoordinator.Constants
        let minimumWindowWidth = Constants.contextualSidebarMinWidth + Constants.contextualSidebarMinPageWidth
        return contextualSidebarPresenter != nil
            && AppWidthObserver.shared.isLargeWidth
            && AppWidthObserver.shared.currentWidth >= minimumWindowWidth
    }

    func presentContextualSidebar(_ viewController: UIViewController) {
        contextualSidebarPresenter?.present(viewController)
    }

    func dismissContextualSidebar(_ viewController: UIViewController, animated: Bool, completion: (() -> Void)?) {
        guard let contextualSidebarPresenter else {
            completion?()
            return
        }
        contextualSidebarPresenter.dismiss(viewController, animated: animated, completion: completion)
    }

    func makeContextualSidebarPresenter() -> AIChatContextualSidebarPresenter? {
        guard let container = viewCoordinator.contextualSidebarContainer,
              let shown = viewCoordinator.constraints.contextualSidebarShown,
              let hidden = viewCoordinator.constraints.contextualSidebarHidden else { return nil }
        return AIChatContextualSidebarPresenter(parent: self,
                                                pageView: viewCoordinator.contentContainer,
                                                pageBackgroundColor: { [weak self] in self?.currentTab?.webView.underPageBackgroundColor },
                                                container: container,
                                                shownConstraint: shown,
                                                hiddenConstraint: hidden)
    }

    /// The sidebar sits beside the page rather than over it, so using the page or the address bar leaves it open.
    var isContextualSurfaceInSidebar: Bool {
        currentTab?.aiChatContextualSheetCoordinator.isSheetInSidebar == true
    }

    /// The sidebar only ever shows the current tab's chat. Closing a tab attaches the next one without
    /// dismissing the closed tab's surface, which would otherwise stay beside the new page.
    func reconcileContextualSidebarWithCurrentTab() {
        guard let presenter = contextualSidebarPresenter,
              let hostedViewController = presenter.hostedViewController,
              hostedViewController !== currentTab?.aiChatContextualSheetCoordinator.sheetViewController else { return }
        presenter.dismiss(hostedViewController, animated: true, completion: nil)
    }

    /// A window narrowed out of the iPad layout has no room for the sidebar, so the page takes the width back.
    func closeContextualSidebarIfItNoLongerFits() {
        guard !canPresentContextualSidebar,
              let coordinator = currentTab?.aiChatContextualSheetCoordinator,
              coordinator.isSheetInSidebar else { return }
        coordinator.dismissSheet(animated: false)
    }
}
