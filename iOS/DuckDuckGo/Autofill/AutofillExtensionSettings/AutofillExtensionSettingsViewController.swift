//
//  AutofillExtensionSettingsViewController.swift
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
import SwiftUI

@available(iOS 18.0, *)
protocol AutofillExtensionSettingsViewControllerDelegate: AnyObject {
    func autofillExtensionSettingsViewController(_ controller: AutofillExtensionSettingsViewController, shouldDisableAuth: Bool)
}

@available(iOS 18.0, *)
class AutofillExtensionSettingsViewController: UIViewController {

    enum Source: String {
        case autofillSettings = "settings"
        case passwordsPromotion = "passwords_promo"
        case inlinePromotion = "inline_promo"
    }

    private let viewModel: AutofillExtensionSettingsViewModel
    weak var delegate: (any AutofillExtensionSettingsViewControllerDelegate)?

    init(source: Source) {
        self.viewModel = AutofillExtensionSettingsViewModel(source: source.rawValue)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        setupView()

        title = UserText.autofillExtensionScreenTitle
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        if isMovingFromParent {
            self.delegate?.autofillExtensionSettingsViewController(self, shouldDisableAuth: false)
        }
    }

    private func setupView() {
        viewModel.delegate = self
        let controller = UIHostingController(rootView: AutofillExtensionSettingsView(viewModel: viewModel))
        controller.view.backgroundColor = .clear
        installChildViewController(controller)
    }

}

@available(iOS 18.0, *)
extension AutofillExtensionSettingsViewController: AutofillExtensionSettingsViewModelDelegate {

    func autofillExtensionSettingsViewModel(_ viewModel: AutofillExtensionSettingsViewModel, shouldDisableAuth: Bool) {
        delegate?.autofillExtensionSettingsViewController(self, shouldDisableAuth: shouldDisableAuth)
    }
}
