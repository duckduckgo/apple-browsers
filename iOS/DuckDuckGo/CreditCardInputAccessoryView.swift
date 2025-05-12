//
//  CreditCardInputAccessoryView.swift
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

import Foundation
import UIKit
import SwiftUI
import BrowserServicesKit


class CreditCardInputAccessoryView: UIView {
    
    private var creditCards: [CreditCardRowViewModel] = []
    private var hostingController: UIHostingController<CreditCardInputAccessoryContent>?
    var onCardSelected: ((SecureVaultModels.CreditCard?) -> Void)?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        // Initial empty view
        updateSuggestions([])
    }
    
    func updateSuggestions(_ creditCards: [CreditCardRowViewModel]) {
        self.creditCards = creditCards
        
        // Remove previous hosting view if it exists
        hostingController?.view.removeFromSuperview()
        hostingController?.removeFromParent()
        
        let suggestionsView = CreditCardInputAccessoryContent(
            creditCards: creditCards,
            onSuggestionSelected: { [weak self] suggestion in
                self?.onCardSelected?(suggestion?.creditCard)
            }
        )
        
        // Create and add the hosting controller
        let hostingController = UIHostingController(rootView: suggestionsView)
        self.hostingController = hostingController
        
        // Add to view hierarchy
        addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: bottomAnchor),
            hostingController.view.heightAnchor.constraint(equalToConstant: 56)
        ])
        
        let suggestionsHeight: CGFloat = creditCards.isEmpty ? 0 : 56
        frame.size.height = suggestionsHeight
        
        // Hide if no cards saved
        isHidden = creditCards.isEmpty
    }
    
}
