//
//  ImportPasswordsPromptViewController.swift
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

class ImportPasswordsPromptViewController: UIViewController {

    typealias ImportPasswordsPromptViewControllerCompletion = (_ startImport: Bool) -> Void
    let completion: ImportPasswordsPromptViewControllerCompletion?

    private let keyValueStore: ThrowingKeyValueStoring
    private let manager: AutofillCredentialsImportPresentationManager

    internal init(keyValueStore: ThrowingKeyValueStoring, completion: ImportPasswordsPromptViewControllerCompletion? = nil) {
        self.keyValueStore = keyValueStore
        self.completion = completion
        self.manager = AutofillCredentialsImportPresentationManager(loginImportStateProvider: AutofillLoginImportState(keyValueStore: keyValueStore))

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        setupView()

        Pixel.fire(pixel: .importCredentialsFlowStarted)
    }

    private func setupView() {
        let viewModel = ImportPasswordsPromptViewModel()
        viewModel.delegate = self

        let promptView = ImportPasswordsPromptView(viewModel: viewModel)
        let controller = UIHostingController(rootView: promptView)
        controller.view.backgroundColor = .clear
        presentationController?.delegate = self
        installChildViewController(controller)

        self.view.backgroundColor = UIColor(designSystemColor: .surface)
    }
}

extension ImportPasswordsPromptViewController: UISheetPresentationControllerDelegate {
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        manager.incrementCredentialsImportPromptPresentationCount()
        self.completion?(false)

        Pixel.fire(pixel: .importCredentialsFlowCancelled)
    }
}

extension ImportPasswordsPromptViewController: ImportPasswordsPromptViewModelDelegate {
    func importPasswordsPromptViewModelDidSelectImportPasswords(_ viewModel: ImportPasswordsPromptViewModel) {
        self.dismiss(animated: true) { [weak self] in
            self?.completion?(true)
        }
    }

    func importPasswordsPromptViewModelDidSelectSetUpLater(_ viewModel: ImportPasswordsPromptViewModel) {
        manager.autofillUserScriptDidRequestPermanentCredentialsImportPromptDismissal()

        self.dismiss(animated: true) { [weak self] in
            self?.completion?(false)
        }
        Pixel.fire(pixel: .importCredentialsPromptNeverAgainClicked)
    }
    
    func importPasswordsPromptViewModelDidDismiss(_ viewModel: ImportPasswordsPromptViewModel) {
        manager.incrementCredentialsImportPromptPresentationCount()
        self.dismiss(animated: true) { [weak self] in
            self?.completion?(false)
        }
        Pixel.fire(pixel: .importCredentialsFlowCancelled)
    }

    func importPasswordsPromptViewModelDidResizeContent(_ viewModel: ImportPasswordsPromptViewModel, contentHeight: CGFloat) {
        if #available(iOS 16.0, *) {
            if let sheetPresentationController = self.presentationController as? UISheetPresentationController {
                sheetPresentationController.animateChanges {
                    sheetPresentationController.detents = [.custom(resolver: { _ in contentHeight })]
                }
            }
        }
    }
}
