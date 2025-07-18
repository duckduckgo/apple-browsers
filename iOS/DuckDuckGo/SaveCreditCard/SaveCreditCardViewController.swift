//
//  SaveCreditCardViewController.swift
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

protocol SaveCreditCardViewControllerDelegate: AnyObject {
    func saveCreditCardViewController(_ viewController: SaveCreditCardViewController, didSaveCreditCard card: SecureVaultModels.CreditCard)
    func saveCreditCardViewControllerConfirmKeepUsing(_ viewController: SaveCreditCardViewController)
}

class SaveCreditCardViewController: UIViewController {
    
    weak var delegate: SaveCreditCardViewControllerDelegate?
    let viewModel: SaveCreditCardViewModel
    
    internal init(creditCard: SecureVaultModels.CreditCard, accountDomain: String, domainLastShownOn: String? = nil) {
        viewModel = .init(creditCard: creditCard, accountDomain: accountDomain, domainLastShownOn: domainLastShownOn)
        
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
        
        let controller = UIHostingController(rootView: SaveCreditCardView(viewModel: viewModel))
        controller.view.backgroundColor = .clear
        presentationController?.delegate = self
        installChildViewController(controller)
    }
}

extension SaveCreditCardViewController: UISheetPresentationControllerDelegate {
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        Pixel.fire(pixel: .autofillCardsSaveCardInlineDismissed)
    }
}

extension SaveCreditCardViewController: SaveCreditCardViewModelDelegate {
    func saveCreditCardViewModelDidSave(_ viewModel: SaveCreditCardViewModel, creditCard: SecureVaultModels.CreditCard) {
        dismiss(animated: true)
        
        self.delegate?.saveCreditCardViewController(self, didSaveCreditCard: creditCard)
    }
    
    func saveCreditCardViewModelCancel(_ viewModel: SaveCreditCardViewModel) {
        dismiss(animated: true)
    }
    
    func saveCreditCardViewModelConfirmKeepUsing(_ viewModel: SaveCreditCardViewModel) {
        delegate?.saveCreditCardViewControllerConfirmKeepUsing(self)
    }
    
    func saveCreditCardViewModelDidResizeContent(_ viewModel: SaveCreditCardViewModel, contentHeight: CGFloat) {
        if #available(iOS 16.0, *) {
            if let sheetPresentationController = self.presentationController as? UISheetPresentationController {
                sheetPresentationController.animateChanges {
                    sheetPresentationController.detents = [.custom(resolver: { _ in contentHeight })]
                }
            }
        }
    }
}
