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
        canPresentContextualSidebar(withMargin: 0)
    }

    private func canPresentContextualSidebar(withMargin margin: CGFloat) -> Bool {
        typealias Constants = MainViewCoordinator.Constants
        let minimumWindowWidth = Constants.contextualSidebarMinWidth + Constants.contextualSidebarMinPageWidth
        return contextualSidebarPresenter != nil
            && AppWidthObserver.shared.isLargeWidth
            && AppWidthObserver.shared.currentWidth >= minimumWindowWidth + margin
    }

    func presentContextualSidebar(_ viewController: UIViewController, coversPage: Bool) {
        contextualSidebarPresenter?.present(viewController, coversPage: coversPage)
    }

    func dismissContextualSidebar(_ viewController: UIViewController, animated: Bool, completion: (() -> Void)?) {
        guard let contextualSidebarPresenter else {
            completion?()
            return
        }
        contextualSidebarPresenter.dismiss(viewController, animated: animated, completion: completion)
    }

    func detachContextualSidebar(_ viewController: UIViewController, animated: Bool) {
        contextualSidebarPresenter?.detach(viewController, animated: animated)
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
        // The new tab is already on screen, so a snapshot of the page would show the closed one.
        presenter.dismiss(hostedViewController, animated: true, coversPage: false, completion: nil)
    }

    /// Runs on every step of a window resize, and on rotation, before the new size lands. The chat follows the window
    /// both ways mid-drag: a sidebar that stops fitting hands it to a sheet, and a sheet moves back once it clearly fits
    /// again, or when the drag ends.
    func contextualSurfaceWillTransition(with transitionCoordinator: UIViewControllerTransitionCoordinator) {
        guard let coordinator = currentTab?.aiChatContextualSheetCoordinator else { return }
        // A rotation animates its own change, which covers the column leaving at once.
        if transitionCoordinator.isAnimated, coordinator.isSheetInSidebar, !canPresentContextualSidebar {
            coordinator.parkSurfaceForResize(animated: false)
        }
        let isLiveResizeStep = !transitionCoordinator.isAnimated
        transitionCoordinator.animate(alongsideTransition: nil) { [weak self, weak coordinator] _ in
            guard let self, let coordinator else { return }
            // A live resize step runs with animations off, so the column's exit starts here, once the step is done.
            if coordinator.isSheetInSidebar, !self.canPresentContextualSidebar {
                coordinator.parkSurfaceForResize(animated: true)
            }
            // A drag hovering around the sidebar's width would otherwise flip the chat back and forth on every step.
            let margin = isLiveResizeStep ? MainViewCoordinator.Constants.contextualSidebarResizeHysteresis : 0
            if coordinator.hasParkedSurface || self.canPresentContextualSidebar(withMargin: margin) {
                coordinator.adaptSurface(toPresenter: self)
            }
            self.adaptContextualSurfaceWhenResizeEnds()
        }
    }

    /// A step that lands while the sheet is still sliding in can't move it, so the end of the drag settles it.
    private func adaptContextualSurfaceWhenResizeEnds() {
        guard #available(iOS 26, *),
              let scene = view.window?.windowScene,
              scene.effectiveGeometry.isInteractivelyResizing,
              contextualSurfaceResizeEndObservation == nil else { return }
        contextualSurfaceResizeEndObservation = scene.observe(\.effectiveGeometry) { [weak self] scene, _ in
            MainActor.assumeIsolated {
                guard let self, !scene.effectiveGeometry.isInteractivelyResizing else { return }
                self.contextualSurfaceResizeEndObservation = nil
                self.currentTab?.aiChatContextualSheetCoordinator.adaptSurface(toPresenter: self)
            }
        }
    }
}
