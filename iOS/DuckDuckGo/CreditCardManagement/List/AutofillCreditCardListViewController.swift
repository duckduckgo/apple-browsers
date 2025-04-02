//
//  AutofillCreditCardListViewController.swift
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
import SwiftUI

final class AutofillCreditCardListViewController: UIViewController {
    
    private var viewModel: AutofillCreditCardListViewModel
    private let secureVault: (any AutofillSecureVault)?
    private lazy var addBarButtonItem: UIBarButtonItem = {
        UIBarButtonItem(image: UIImage(named: "Add-24"),
                        style: .plain,
                        target: self,
                        action: #selector(addButtonPressed))
    }()
    
    init(secureVault: (any AutofillSecureVault)? = nil) {
        self.secureVault = secureVault
        self.viewModel = AutofillCreditCardListViewModel(secureVault: secureVault)
        
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        setupView()
        
        title = UserText.autofillCreditCardListTitle
    }
    
    private func setupView() {
        viewModel.delegate = self
        
        let controller = UIHostingController(rootView: AutofillCreditCardListView(viewModel: viewModel))
        controller.view.backgroundColor = .clear
        installChildViewController(controller)
        
        updateNavigationBarButtons()
    }
    
    private func updateNavigationBarButtons() {
        navigationItem.rightBarButtonItems = [addBarButtonItem]
    }

    @objc
    private func addButtonPressed() {
        let viewController = AutofillCreditCardDetailsViewController(secureVault: secureVault)
        viewController.delegate = self
        let detailsNavigationController = UINavigationController(rootViewController: viewController)
        detailsNavigationController.navigationBar.tintColor = UIColor(Color(designSystemColor: .textPrimary))
        navigationController?.present(detailsNavigationController, animated: true)
    }
    
    private func presentCardDetails(for card: SecureVaultModels.CreditCard) {
        let viewController = AutofillCreditCardDetailsViewController(secureVault: secureVault, card: card)
        viewController.delegate = self
        navigationController?.pushViewController(viewController, animated: true)
    }
}

extension AutofillCreditCardListViewController: AutofillCreditCardListViewModelDelegate {

    func autofillCreditCardListViewModelDidSelectCard(_ viewModel: AutofillCreditCardListViewModel, card: SecureVaultModels.CreditCard) {
        presentCardDetails(for: card)
    }
    
}

extension AutofillCreditCardListViewController: AutofillCreditCardDetailsViewControllerDelegate {

    func autofillCreditCardDetailsViewControllerDidSave(_ controller: AutofillCreditCardDetailsViewController, card: SecureVaultModels.CreditCard?) {
        viewModel.refreshData()
    }

    func autofillCreditCardDetailsViewControllerDelete(card: SecureVaultModels.CreditCard) {
        viewModel.deleteCard(card)
    }

}
