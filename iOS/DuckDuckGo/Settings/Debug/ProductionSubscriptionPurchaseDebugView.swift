//
//  ProductionSubscriptionPurchaseDebugView.swift
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

import SwiftUI
import Subscription
import Core

/// Closure type for handling subscription selection through the user script handler
/// Parameters: (productId: String, changeType: String?) where changeType is "upgrade", "downgrade", or nil for new purchase
typealias SubscriptionSelectionHandler = (String, String?) async -> Void

struct ProductionSubscriptionPurchaseDebugView: View {
    @StateObject private var viewModel: ProductionSubscriptionPurchaseViewModel

    init(subscriptionSelectionHandler: SubscriptionSelectionHandler? = nil) {
        _viewModel = StateObject(wrappedValue: ProductionSubscriptionPurchaseViewModel(
            subscriptionSelectionHandler: subscriptionSelectionHandler
        ))
    }
    
    var body: some View {
        List {
            currentSubscriptionsSection
            availableSubscriptionsSection
            statusSection
            accountSection
        }
        .navigationTitle("Change Tier")
        .onAppear {
            Task {
                await viewModel.loadExistingExternalID()
                await viewModel.loadPurchasedProductIDs()
                await viewModel.loadAvailableProducts()
            }
        }
        .alert("Purchase Result", isPresented: $viewModel.showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.alertMessage)
        }
    }
    
    private var accountSection: some View {
        Section(header: Text("Account")) {
            if viewModel.isLoadingExternalID {
                HStack {
                    Text("Checking for existing account...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else if let externalID = viewModel.existingExternalID {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Will attach to EXISTING account")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                    Text("External ID: \(externalID)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Will create NEW account")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                    Text("No existing subscription found")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private var currentSubscriptionsSection: some View {
        Section(header: Text("Current Subscriptions")) {
            if let productIDs = viewModel.purchasedProductIDs, !productIDs.isEmpty {
                ForEach(productIDs, id: \.self) { productID in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.displayName(for: productID))
                            .font(.subheadline)
                        Text(productID)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                Text("No active subscriptions")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var availableSubscriptionsSection: some View {
        Section(header: Text("Available Products")) {
            if viewModel.isLoadingProducts {
                HStack {
                    Text("Loading available products...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else if viewModel.availableSubscriptions.isEmpty {
                Text("No subscriptions available")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(viewModel.availableSubscriptions, id: \.self) { identifier in
                    subscriptionRow(identifier: identifier)
                }
            }
        }
    }
    
    @ViewBuilder
    private var statusSection: some View {
        if let message = viewModel.statusMessage {
            Section(header: Text("Status")) {
                Text(message)
                    .font(.caption)
                    .foregroundColor(viewModel.isError ? .red : .green)
            }
        }
    }
    
    private func subscriptionRow(identifier: String) -> some View {
        Button {
            Task {
                await viewModel.purchaseSubscription(identifier: identifier)
            }
        } label: {
            HStack {
                VStack(alignment: .leading) {
                    Text(viewModel.displayName(for: identifier))
                        .font(.body)
                    Text(identifier)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
        }
        .disabled(viewModel.isLoading || viewModel.isLoadingExternalID || viewModel.isLoadingProducts)
    }
}

@MainActor
class ProductionSubscriptionPurchaseViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var statusMessage: String?
    @Published var isError = false
    @Published var showAlert = false
    @Published var alertMessage = ""
    @Published var existingExternalID: String?
    @Published var isLoadingExternalID = true
    @Published var purchasedProductIDs: [String]?
    @Published var availableSubscriptions: [String] = []
    @Published var isLoadingProducts = true

    private let subscriptionSelectionHandler: SubscriptionSelectionHandler?

    init(subscriptionSelectionHandler: SubscriptionSelectionHandler? = nil) {
        self.subscriptionSelectionHandler = subscriptionSelectionHandler
    }
    
    func loadExistingExternalID() async {
        isLoadingExternalID = true
        let manager = AppDependencyProvider.shared.subscriptionManager
        do {
            // Try to get existing external ID from authenticated account
            let tokenContainer = try await manager.getTokenContainer(policy: .local)
            existingExternalID = tokenContainer.decodedAccessToken.externalID
            Logger.subscription.info("[ProductionSubscriptionDebug] Found existing external ID: \(self.existingExternalID ?? "nil")")
        } catch {
            // No existing account, will create new
            existingExternalID = nil
            Logger.subscription.info("[ProductionSubscriptionDebug] No existing account found, will create new")
        }
        isLoadingExternalID = false
    }
    
    func loadPurchasedProductIDs() async {
        let manager = AppDependencyProvider.shared.subscriptionManager
        let productIDs = manager.storePurchaseManager().purchasedProductIDs
        purchasedProductIDs = productIDs
        Logger.subscription.info("[ProductionSubscriptionDebug] Found \(productIDs.count) purchased product(s): \(productIDs)")
    }
    
    func loadAvailableProducts() async {
        isLoadingProducts = true
        let manager = AppDependencyProvider.shared.subscriptionManager
        // Cast to DefaultStorePurchaseManager to access availableProducts
        guard let defaultManager = manager.storePurchaseManager() as? DefaultStorePurchaseManager else {
            Logger.subscription.error("[ProductionSubscriptionDebug] Could not cast to DefaultStorePurchaseManager")
            isLoadingProducts = false
            return
        }
        
        // Update available products from StoreKit first
        await defaultManager.updateAvailableProducts()
        
        let products = defaultManager.availableProducts
        let productIDs = products.map { $0.id }
        
        availableSubscriptions = productIDs.sorted()
        
        Logger.subscription.info("[ProductionSubscriptionDebug] Loaded \(productIDs.count) available products")
        
        isLoadingProducts = false
    }
    
    func displayName(for identifier: String) -> String {
        if identifier.contains("monthly") {
            if identifier.contains("freetrial") {
                return "Monthly (with Free Trial)"
            }
            return "Monthly"
        } else if identifier.contains("yearly") {
            if identifier.contains("freetrial") {
                return "Yearly (with Free Trial)"
            }
            return "Yearly"
        }
        return identifier
    }
    
    func purchaseSubscription(identifier: String) async {
        isLoading = true
        isError = false

        // Determine if this is a tier change (has existing subscription)
        let isTierChange = existingExternalID != nil && !(purchasedProductIDs?.isEmpty ?? true)
        let changeType: String? = isTierChange ? "upgrade" : nil

        if let handler = subscriptionSelectionHandler {
            // Use the subscription selection handler (calls subscriptionChangeSelected or subscriptionSelected)
            let actionType = isTierChange ? "tier change" : "purchase"
            statusMessage = "Starting \(actionType) for \(displayName(for: identifier))..."
            Logger.subscription.info("[ProductionSubscriptionDebug] Using subscriptionSelectionHandler for \(actionType): \(identifier)")

            let previousProductIDs = purchasedProductIDs ?? []
            await handler(identifier, changeType)

            // Refresh purchased product IDs after handler completes
            await loadPurchasedProductIDs()

            // Update status based on outcome
            if let updatedPurchasedIDs = purchasedProductIDs, updatedPurchasedIDs.contains(identifier) {
                statusMessage = "✅ \(actionType.capitalized) completed for \(displayName(for: identifier))"
                isError = false
            } else if previousProductIDs != (purchasedProductIDs ?? []) {
                statusMessage = "✅ Subscription updated"
                isError = false
            } else {
                // Cancelled or failed - handler shows its own UI
                statusMessage = nil
            }

            isLoading = false
            return
        }

        // Fallback to direct purchase (legacy behavior)
        statusMessage = "Starting purchase for \(displayName(for: identifier))..."
        
        // Use existing external ID if available, otherwise generate new
        let externalID = existingExternalID ?? UUID().uuidString
        let isNewAccount = existingExternalID == nil
        
        Logger.subscription.info("[ProductionSubscriptionDebug] Using external ID: \(externalID) (new: \(isNewAccount))")
        
        // Direct purchase bypassing AppStorePurchaseFlow
        let manager = AppDependencyProvider.shared.subscriptionManager
        let result = await manager.storePurchaseManager().purchaseSubscription(with: identifier, externalID: externalID, includeProTier: true)

        switch result {
        case .success:
            let accountStatus = isNewAccount ? "NEW account created" : "Attached to EXISTING account"
            statusMessage = "✅ Purchase successful!"
            isError = false
            alertMessage = "Purchase successful! \(accountStatus)\n\nExternal ID: \(externalID)"
            showAlert = true
            
            // Store the external ID for future purchases if this was a new account
            if isNewAccount {
                existingExternalID = externalID
                Logger.subscription.info("[ProductionSubscriptionDebug] Stored new external ID for future purchases: \(externalID)")
            }
            
            // Refresh purchased product IDs to show the new purchase
            await loadPurchasedProductIDs()
            
            Logger.subscription.info("[ProductionSubscriptionDebug] Purchase successful: \(identifier)")
            
        case .failure(let error):
            statusMessage = "❌ Purchase failed: \(error.localizedDescription)"
            isError = true
            Logger.subscription.error("[ProductionSubscriptionDebug] Purchase failed: \(error.localizedDescription)")
        }
        
        isLoading = false
    }
}
