//
//  AutofillCreditCardDetailsViewController.swift
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
import Core
import SwiftUI

protocol AutofillCreditCardDetailsViewControllerDelegate: AnyObject {
    func autofillCreditCardDetailsViewControllerDidSave(_ controller: AutofillCreditCardDetailsViewController, card: SecureVaultModels.CreditCard?)
    func autofillCreditCardDetailsViewControllerDelete(card: SecureVaultModels.CreditCard)
}

final class AutofillCreditCardDetailsViewController: UIViewController {
    
    weak var delegate: AutofillCreditCardDetailsViewControllerDelegate?
    
    private let viewModel: AutofillCreditCardDetailsViewModel
    private var cancellables: Set<AnyCancellable> = []
    
    private lazy var saveBarButtonItem: UIBarButtonItem = {
        let barButtonItem = UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(save))
        let attributes = [NSAttributedString.Key.font: UIFont.preferredFont(forTextStyle: .headline)]
        barButtonItem.setTitleTextAttributes(attributes, for: [.normal])
        barButtonItem.setTitleTextAttributes(attributes, for: [.disabled])
        return barButtonItem
    }()
    
    private lazy var editBarButtonItem: UIBarButtonItem = {
        let barButtonItem = UIBarButtonItem(barButtonSystemItem: .edit, target: self, action: #selector(toggleEditMode))
        let attributes = [NSAttributedString.Key.font: UIFont.preferredFont(forTextStyle: .headline)]
        barButtonItem.setTitleTextAttributes(attributes, for: .normal)
        return barButtonItem
    }()
    
    init(authenticator: AutofillLoginListAuthenticator, secureVault: (any AutofillSecureVault)? = nil, card: SecureVaultModels.CreditCard? = nil) {
        self.viewModel = AutofillCreditCardDetailsViewModel(authenticator: authenticator, secureVault: secureVault, creditCard: card)
        
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupView()
        setupObservers()
        setupCancellables()
        setupNavigationBar()
    }
    
    private func setupObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActiveCallback), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appWillResignActiveCallback), name: UIApplication.willResignActiveNotification, object: nil)
    }
    
    @objc private func appDidBecomeActiveCallback() {
        authenticate()
    }
    
    @objc private func appWillResignActiveCallback() {
        viewModel.lockUI()
    }
    
    private func setupView() {
        viewModel.delegate = self
        
        let controller = UIHostingController(rootView: AutofillCreditCardDetailsView(viewModel: viewModel))
        controller.view.backgroundColor = .clear
        installChildViewController(controller)
    }
    
    private func setupNavigationBar() {
        title = viewModel.navigationTitle
        
        if viewModel.authenticationRequired {
            saveBarButtonItem.isEnabled = false
            editBarButtonItem.isEnabled = false
        } else {
            switch viewModel.viewMode {
            case .edit, .new:
                saveBarButtonItem.isEnabled = viewModel.canSave
                navigationItem.rightBarButtonItem = saveBarButtonItem
                navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
                
            case .view:
                editBarButtonItem.isEnabled = true
                navigationItem.rightBarButtonItem = editBarButtonItem
                navigationItem.leftBarButtonItem = nil
            }
        }
    }
    
    private func setupCancellables() {
        viewModel.$viewMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.setupNavigationBar()
            }
            .store(in: &cancellables)
        
        Publishers.MergeMany(
            viewModel.$cardNumber,
            viewModel.$formattedExpiration,
            viewModel.$cardSecurityCode,
            viewModel.$cardholderName,
            viewModel.$cardTitle)
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.setupNavigationBar()
        }
        .store(in: &cancellables)
        
        viewModel.$authenticationRequired
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.setupNavigationBar()
            }
            .store(in: &cancellables)
    }
    
    @objc private func toggleEditMode() {
        viewModel.toggleEditMode()
    }
    
    @objc private func save() {
        viewModel.save()
    }
    
    @objc private func cancel() {
        switch viewModel.viewMode {
        case .new:
            dismiss(animated: true)
        default:
            toggleEditMode()
        }
    }
    
    private func authenticate() {
        viewModel.authenticate {[weak self] error in
            guard let self = self else { return }
            
            if error != nil {
                dismiss(animated: true)
            }
        }
    }
}

extension AutofillCreditCardDetailsViewController: AutofillCreditCardDetailsViewModelDelegate {
    
    func autofillCreditCardDetailsViewModelDidSave() {
        switch viewModel.viewMode {
        case .new:
            dismiss(animated: true) { [weak self] in
                guard let self = self else { return }
                self.delegate?.autofillCreditCardDetailsViewControllerDidSave(self, card: viewModel.creditCard)
            }
        default:
            delegate?.autofillCreditCardDetailsViewControllerDidSave(self, card: nil)
        }
    }
    
    func autofillCreditCardDetailsViewModelDelete(card: SecureVaultModels.CreditCard) {
        delegate?.autofillCreditCardDetailsViewControllerDelete(card: card)
        navigationController?.popViewController(animated: true)
        
    }
    
    func autofillCreditCardDetailsViewModelDismiss() {
        navigationController?.dismiss(animated: true)
    }
}
