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
import Combine
import SwiftUI

final class AutofillCreditCardListViewController: UIViewController {
    
    private var viewModel: AutofillCreditCardListViewModel
    private let secureVault: (any AutofillSecureVault)?
    private var cancellables: Set<AnyCancellable> = []
    
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
        
        setupCancellables()
        setupObservers()
        authenticate()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupView()
        
        title = UserText.autofillCreditCardListTitle
    }
    
    private func setupCancellables() {
        viewModel.$viewState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateNavigationBarButtons()
            }
            .store(in: &cancellables)
    }
    
    private func setupObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActiveCallback), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appWillResignActiveCallback), name: UIApplication.willResignActiveNotification, object: nil)
    }
    
    @objc private func appDidBecomeActiveCallback() {
        guard !(navigationController?.topViewController is AutofillCreditCardDetailsViewController) else { return }

        if let presentedNavController = navigationController?.presentedViewController as? UINavigationController,
           presentedNavController.topViewController is AutofillCreditCardDetailsViewController {
            return
        }
        
        authenticate()
    }
    
    @objc private func appWillResignActiveCallback() {
        viewModel.lockUI()
    }
    
    private func setupView() {
        viewModel.delegate = self
        
        let controller = UIHostingController(rootView: AutofillCreditCardListView(viewModel: viewModel))
        controller.view.backgroundColor = .clear
        installChildViewController(controller)
        
        updateNavigationBarButtons()
    }
    
    private func updateNavigationBarButtons() {
        switch viewModel.viewState {
        case .authLocked, .noAuthAvailable:
            navigationItem.rightBarButtonItems = []
        case .empty, .showItems:
            navigationItem.rightBarButtonItems = [addBarButtonItem]
        }
    }
    
    private func authenticate() {
        viewModel.authenticate {[weak self] error in
            guard let self = self else { return }
            
            if error != nil {
                if error == .noAuthAvailable {
                    let alert = UIAlertController(title: UserText.autofillCreditCardsNoAuthViewTitle, message: UserText.autofillCreditCardsNoAuthViewSubtitle, preferredStyle: .alert)
                    alert.addAction(title: UserText.actionOK) { [weak self] in
                        self?.navigationController?.popViewController(animated: true)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                        self?.present(alert, animated: true)
                    }
                } else {
                    navigationController?.popViewController(animated: true)
                }
            }
        }
    }
    
    @objc
    private func addButtonPressed() {
        let viewController = AutofillCreditCardDetailsViewController(authenticator: viewModel.authenticator, secureVault: secureVault)
        viewController.delegate = self
        let detailsNavigationController = UINavigationController(rootViewController: viewController)
        detailsNavigationController.navigationBar.tintColor = UIColor(Color(designSystemColor: .textPrimary))
        navigationController?.present(detailsNavigationController, animated: true)
    }
    
    private func presentCardDetails(for card: SecureVaultModels.CreditCard) {
        let viewController = AutofillCreditCardDetailsViewController(authenticator: viewModel.authenticator, secureVault: secureVault, card: card)
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
