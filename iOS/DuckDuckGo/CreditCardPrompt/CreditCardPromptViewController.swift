//
//  CreditCardPromptViewController.swift
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
import BrowserServicesKit
import Core
import SwiftUI

class CreditCardPromptViewController: UIViewController {
    
    typealias CreditCardPromptViewControllerCompletion = (_ creditCard: SecureVaultModels.CreditCard?) -> Void
    
    let completion: CreditCardPromptViewControllerCompletion?
    let viewModel: CreditCardPromptViewModel
    private let authenticator = AutofillLoginListAuthenticator(reason: UserText.autofillCreditCardFillPromptAuthentication,
                                                               cancelTitle: UserText.autofillLoginListAuthenticationCancelButton)
    
    
    internal init(creditCards: [SecureVaultModels.CreditCard],
                  completion: CreditCardPromptViewControllerCompletion?) {
        viewModel = .init(creditCards: creditCards)
        self.completion = completion
        
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.view.backgroundColor = UIColor(designSystemColor: .surface)
        
        setupView()
    }
    
    private func setupView() {
        viewModel.delegate = self
        
        let controller = UIHostingController(rootView: CreditCardPromptView(viewModel: viewModel))
        controller.view.backgroundColor = .clear
        presentationController?.delegate = self
        installChildViewController(controller)
    }
}

extension CreditCardPromptViewController: UISheetPresentationControllerDelegate {
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        Pixel.fire(pixel: .autofillCardsFillCardManualInlineDismissed)

        self.completion?(nil)
    }
}

extension CreditCardPromptViewController: CreditCardPromptViewModelDelegate {
    
    func creditCardPromptViewModel(_ viewModel: CreditCardPromptViewModel, didSelectCreditCard creditCard: SecureVaultModels.CreditCard) {
        
        if AppDependencyProvider.shared.autofillLoginSession.isSessionValid {
            dismiss(animated: true) { [weak self] in
                self?.completion?(creditCard)
            }
            return
        }
        
        authenticator.authenticate { [weak self] error in
            if error != nil {
                AppDependencyProvider.shared.autofillLoginSession.endSession()
                self?.dismiss(animated: true) {
                    self?.completion?(nil)
                }
                return
            }
            
            self?.dismiss(animated: true) {
                self?.completion?(creditCard)
                AppDependencyProvider.shared.autofillLoginSession.startSession()
            }
        }
    }
    
    func creditCardPromptViewModelCancel(_ viewModel: CreditCardPromptViewModel) {
        dismiss(animated: true) { [weak self] in
            self?.completion?(nil)
        }
    }
    
    func creditCardPromptViewModelDidResizeContent(_ viewModel: CreditCardPromptViewModel, contentHeight: CGFloat) {
        if #available(iOS 16.0, *) {
            if let sheetPresentationController = self.presentationController as? UISheetPresentationController {
                sheetPresentationController.animateChanges {
                    sheetPresentationController.detents = [.custom(resolver: { _ in contentHeight })]
                }
            }
        }
    }
}
