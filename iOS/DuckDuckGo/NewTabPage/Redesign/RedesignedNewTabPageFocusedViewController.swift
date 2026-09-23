//
//  RedesignedNewTabPageFocusedViewController.swift
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

/// Arranges the existing focused content within the browser's input layout.
/// The content controller stays a child of the browser so changing presentation does not restart
/// its appearance lifecycle or the suggestions surfaces owned by its descendants.
final class RedesignedNewTabPageFocusedViewController: UIViewController {

    private static let boundsConstraintIdentifier = "FocusedContentContainer.bounds"

    static func install(_ contentViewController: UIViewController,
                        in parent: UIViewController,
                        container: UIView) {
        guard contentViewController.parent == nil else { return }
        embed(contentViewController, in: parent, container: container)
    }

    static func updateContainment(of contentViewController: UIViewController,
                                  in parent: UIViewController,
                                  container: UIView,
                                  usesFocusedContainer: Bool) {
        if contentViewController.parent == nil {
            install(contentViewController, in: parent, container: container)
        }
        guard contentViewController.parent === parent else { return }
        let focusedController = parent.children
            .compactMap { $0 as? RedesignedNewTabPageFocusedViewController }
            .first { $0.viewIfLoaded?.superview === container }
        if usesFocusedContainer {
            guard focusedController == nil else { return }
            let focusedController = RedesignedNewTabPageFocusedViewController()
            embed(focusedController, in: parent, container: container)
            move(contentViewController.view, into: focusedController.view)
        } else {
            guard let focusedController else { return }
            move(contentViewController.view, into: container)
            focusedController.willMove(toParent: nil)
            focusedController.view.removeFromSuperview()
            focusedController.removeFromParent()
        }
    }

    private static func embed(_ child: UIViewController, in parent: UIViewController, container: UIView) {
        parent.addChild(child)
        move(child.view, into: container)
        child.didMove(toParent: parent)
    }

    private static func move(_ view: UIView, into container: UIView) {
        // A move into a descendant keeps the old ancestor constraints alive unless removed explicitly.
        let previousConstraints = view.superview?.constraints.filter {
            $0.identifier == boundsConstraintIdentifier && $0.firstItem as? UIView === view
        } ?? []
        NSLayoutConstraint.deactivate(previousConstraints)
        view.translatesAutoresizingMaskIntoConstraints = false
        // Reattach directly within the same window, without a detached appearance transition.
        container.addSubview(view)
        let constraints = [
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ]
        constraints.forEach { $0.identifier = boundsConstraintIdentifier }
        NSLayoutConstraint.activate(constraints)
    }
}
