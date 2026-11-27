//
//  NewTabPageInputSlot.swift
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

final class NewTabPageInputSlotBlock: NewTabPageBlock {

    let id = NewTabPageBlockID.searchInput

    let slot = NewTabPageInputSlotViewController()

    var viewController: UIViewController { slot }
}

final class NewTabPageInputSlotViewController: UIViewController {

    private enum Metrics {
        static let emptyHeight: CGFloat = 64
    }

    private lazy var heightConstraint = view.heightAnchor.constraint(equalToConstant: Metrics.emptyHeight)

    var parkedViewController: UIViewController? {
        children.first
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        heightConstraint.isActive = true
    }

    func park(_ inputViewController: UIViewController) {
        loadViewIfNeeded()
        inputViewController.detachFromParent()
        addChild(inputViewController)
        let inputView: UIView = inputViewController.view
        inputView.transform = .identity
        inputView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(inputView)
        NSLayoutConstraint.activate([
            inputView.topAnchor.constraint(equalTo: view.topAnchor),
            inputView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inputView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        inputViewController.didMove(toParent: self)
    }

    func setHeight(_ height: CGFloat) {
        guard height > 0, heightConstraint.constant != height else { return }
        heightConstraint.constant = height
        view.superview?.setNeedsLayout()
    }
}
