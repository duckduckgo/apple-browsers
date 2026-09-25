//
//  StartupOnboardingCover.swift
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

final class StartupOnboardingCover {

    private weak var parentViewController: UIViewController?
    private let fallbackBackgroundColor: UIColor

    private var coverViewController: UIViewController?
    private var coverView: UIView?

    var isAttached: Bool {
        coverView != nil
    }

    init(parentViewController: UIViewController, fallbackBackgroundColor: UIColor) {
        self.parentViewController = parentViewController
        self.fallbackBackgroundColor = fallbackBackgroundColor
    }

    func attach() {
        guard !isAttached, let parentViewController else { return }

        let coverView = makeCoverView(parentViewController: parentViewController)
        coverView.translatesAutoresizingMaskIntoConstraints = false
        parentViewController.view.addSubview(coverView)

        NSLayoutConstraint.activate([
            coverView.topAnchor.constraint(equalTo: parentViewController.view.topAnchor),
            coverView.leadingAnchor.constraint(equalTo: parentViewController.view.leadingAnchor),
            coverView.trailingAnchor.constraint(equalTo: parentViewController.view.trailingAnchor),
            coverView.bottomAnchor.constraint(equalTo: parentViewController.view.bottomAnchor)
        ])

        parentViewController.view.bringSubviewToFront(coverView)
        coverViewController?.didMove(toParent: parentViewController)
        self.coverView = coverView
    }

    func bringToFront() {
        guard let parentViewController, let coverView else { return }
        parentViewController.view.bringSubviewToFront(coverView)
    }

    func detach() {
        coverViewController?.willMove(toParent: nil)
        coverViewController?.view.removeFromSuperview()
        coverViewController?.removeFromParent()
        coverViewController = nil

        coverView?.removeFromSuperview()
        coverView = nil
    }

    private func makeCoverView(parentViewController: UIViewController) -> UIView {
        if let coverViewController = UIStoryboard(name: "LaunchScreen", bundle: nil).instantiateInitialViewController() {
            self.coverViewController = coverViewController
            parentViewController.addChild(coverViewController)
            coverViewController.loadViewIfNeeded()
            return coverViewController.view
        }

        assertionFailure("Unable to instantiate LaunchScreen storyboard")

        let fallbackView = UIView()
        fallbackView.backgroundColor = fallbackBackgroundColor
        return fallbackView
    }
}
