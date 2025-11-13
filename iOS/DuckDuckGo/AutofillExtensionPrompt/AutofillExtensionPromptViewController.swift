//
//  AutofillExtensionPromptViewController.swift
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
import Persistence
import SwiftUI
import Core

class AutofillExtensionPromptViewController: UIViewController {

    typealias AutofillExtensionPromptViewControllerCompletion = (_ enableExtension: Bool) -> Void
    let completion: AutofillExtensionPromptViewControllerCompletion

    private let manager: AutofillExtensionPromotionManaging

    internal init(extensionPromotionManager: AutofillExtensionPromotionManaging, completion: @escaping AutofillExtensionPromptViewControllerCompletion) {
        self.completion = completion
        self.manager = extensionPromotionManager

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        setupView()

        manager.markPromotionPresented(for: .browser)
        Pixel.fire(pixel: .autofillExtensionInlinePromoDisplayed)
    }

    private func setupView() {
        let viewModel = AutofillExtensionPromptViewModel()
        viewModel.delegate = self

        let promptView = AutofillExtensionPromptView(viewModel: viewModel)
        let controller = UIHostingController(rootView: promptView)
        controller.view.backgroundColor = .clear
        presentationController?.delegate = self
        installChildViewController(controller)

        self.view.backgroundColor = UIColor(designSystemColor: .surface)
    }
}

extension AutofillExtensionPromptViewController: UISheetPresentationControllerDelegate {
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        Pixel.fire(pixel: .autofillExtensionInlinePromoDismissed)
    }
}

extension AutofillExtensionPromptViewController: AutofillExtensionPromptViewModelDelegate {
    func autofillExtensionPromptViewModelDidSelectEnableExtension(_ viewModel: AutofillExtensionPromptViewModel) {
        Pixel.fire(pixel: .autofillExtensionInlinePromoConfirmed)

        dismiss(animated: true) { [weak self] in
            self?.completion(true)
        }
    }

    func autofillExtensionPromptViewModelDidSelectSetUpLater(_ viewModel: AutofillExtensionPromptViewModel) {
        Pixel.fire(pixel: .autofillExtensionInlinePromoDismissedPermanently)

        manager.markPromotionDismissed(for: .browser)
        dismiss(animated: true)
    }

    func autofillExtensionPromptViewModelDidDismiss(_ viewModel: AutofillExtensionPromptViewModel) {
        Pixel.fire(pixel: .autofillExtensionInlinePromoDismissed)
        dismiss(animated: true)
    }

    func autofillExtensionPromptViewModelDidResizeContent(_ viewModel: AutofillExtensionPromptViewModel, contentHeight: CGFloat) {
        if #available(iOS 16.0, *) {
            if let sheetPresentationController = self.presentationController as? UISheetPresentationController {
                sheetPresentationController.animateChanges {
                    sheetPresentationController.detents = [.custom(resolver: { _ in contentHeight })]
                }
            }
        }
    }
}
