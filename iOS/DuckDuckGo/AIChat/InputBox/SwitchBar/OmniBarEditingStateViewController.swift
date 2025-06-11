//
//  OmniBarEditingStateViewController.swift
//  DuckDuckGo
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

import UIKit
import DesignResourcesKit

final class OmniBarEditingStateViewController: UIViewController {
    var textAreaView: UIView {
        switchBarVC.textEntryViewController.textEntryView
    }

    private lazy var switchBarVC = SwitchBarViewController(switchBarHandler: SwitchBarHandler())

    private var textEntryHeightConstraint: NSLayoutConstraint?

    override func viewDidLoad() {
        super.viewDidLoad()

        installSwitchBarVC()
        self.view.backgroundColor = .clear
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        animateAppearance()
    }

    private func animateAppearance() {
        self.view.layoutIfNeeded()

        UIView.animate(withDuration: 0.25, delay: 0.0, options: [.curveEaseInOut]) {
            self.view.backgroundColor = UIColor(designSystemColor: .background)
            self.switchBarVC.setExpanded(true)
            self.switchBarVC.view.layoutIfNeeded()
        }
    }

    @objc private func dismissAnimated() {
        self.switchBarVC.view.layoutIfNeeded()
        UIView.animate(withDuration: 0.25, delay: 0.0, options: [.curveEaseInOut], animations: {
            self.switchBarVC.setExpanded(false)
            self.switchBarVC.view.layoutIfNeeded()
            self.view.backgroundColor = .clear
        }, completion: { _ in
            self.dismiss(animated: false)
        })
    }

    private func installSwitchBarVC() {
        addChild(switchBarVC)
        view.addSubview(switchBarVC.view)
        switchBarVC.view.translatesAutoresizingMaskIntoConstraints = false

        textEntryHeightConstraint = switchBarVC.view.heightAnchor.constraint(equalToConstant: 44)

        switchBarVC.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor).isActive = true
        switchBarVC.view.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor).isActive = true
        switchBarVC.view.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor).isActive = true

        switchBarVC.didMove(toParent: self)

        switchBarVC.backButton.addTarget(self, action: #selector(dismissAnimated), for: .touchUpInside)
    }
}
