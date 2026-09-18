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

/// Hosts the existing focused content within the bounds supplied by the browser's input layout.
/// Input positioning, transitions, and content eligibility remain with their existing owners.
final class RedesignedNewTabPageFocusedViewController: UIViewController {

    static func updateContainment(of contentViewController: UIViewController,
                                  in parent: UIViewController,
                                  container: UIView,
                                  usesFocusedContainer: Bool) {
        let focusedController = contentViewController.parent as? RedesignedNewTabPageFocusedViewController
        if usesFocusedContainer {
            guard focusedController == nil else { return }
            remove(contentViewController)
            let focusedController = RedesignedNewTabPageFocusedViewController()
            embed(focusedController, in: parent, container: container)
            embed(contentViewController, in: focusedController, container: focusedController.view)
        } else {
            guard contentViewController.parent !== parent else { return }
            remove(contentViewController)
            if let focusedController {
                remove(focusedController)
            }
            embed(contentViewController, in: parent, container: container)
        }
    }

    private static func embed(_ child: UIViewController, in parent: UIViewController, container: UIView) {
        parent.addChild(child)
        child.view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(child.view)
        NSLayoutConstraint.activate([
            child.view.topAnchor.constraint(equalTo: container.topAnchor),
            child.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            child.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            child.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        child.didMove(toParent: parent)
    }

    private static func remove(_ child: UIViewController) {
        guard child.parent != nil else { return }
        child.willMove(toParent: nil)
        child.view.removeFromSuperview()
        child.removeFromParent()
    }
}
