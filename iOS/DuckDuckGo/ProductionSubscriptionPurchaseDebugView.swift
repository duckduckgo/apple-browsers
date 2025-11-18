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

struct ProductionSubscriptionPurchaseDebugView: View {
    @StateObject private var viewModel = ProductionSubscriptionPurchaseViewModel()
    
    var body: some View {
        List {
            warningSection
            accountSection
            usaSubscriptionsSection
            rowSubscriptionsSection
            statusSection
        }
        .navigationTitle("Buy Production Subs")
        .onAppear {
            Task {
                await viewModel.loadExistingExternalID()
            }
        }
        .alert("Purchase Result", isPresented: $viewModel.showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.alertMessage)
        }
    }
    
    private var warningSection: some View {
        Section {
            Text("⚠️ WARNING ⚠️")
                .font(.headline)
                .foregroundColor(.red)
            Text("This will attempt to purchase a REAL production subscription, bypassing all safety checks including existing subscription checks. Use with caution!")
                .font(.subheadline)
                .foregroundColor(.secondary)
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
    
    private var usaSubscriptionsSection: some View {
        Section(header: Text("Production Subscriptions - USA")) {
            ForEach(viewModel.usaSubscriptions, id: \.self) { identifier in
                subscriptionRow(identifier: identifier)
            }
        }
    }
    
    private var rowSubscriptionsSection: some View {
        Section(header: Text("Production Subscriptions - Rest of World")) {
            ForEach(viewModel.rowSubscriptions, id: \.self) { identifier in
                subscriptionRow(identifier: identifier)
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
        .disabled(viewModel.isLoading || viewModel.isLoadingExternalID)
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
    
    // Production subscription identifiers from StoreSubscriptionConfiguration
    let usaSubscriptions = [
        "ddg.privacy.pro.monthly.renews.us",
        "ddg.privacy.pro.yearly.renews.us",
        "ddg.privacy.pro.monthly.renews.us.freetrial",
        "ddg.privacy.pro.yearly.renews.us.freetrial"
    ]
    
    let rowSubscriptions = [
        "ddg.privacy.pro.monthly.renews.row",
        "ddg.privacy.pro.yearly.renews.row",
        "ddg.privacy.pro.monthly.renews.row.freetrial",
        "ddg.privacy.pro.yearly.renews.row.freetrial"
    ]

    
    func loadExistingExternalID() async {
        isLoadingExternalID = true
        guard let manager = AppDependencyProvider.shared.subscriptionManagerV2 else {
            Logger.subscription.error("[ProductionSubscriptionDebug] Subscription manager not available")
            isLoadingExternalID = false
            return
        }
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
        statusMessage = "Starting purchase for \(displayName(for: identifier))..."
        
        // Use existing external ID if available, otherwise generate new
        let externalID = existingExternalID ?? UUID().uuidString
        let isNewAccount = existingExternalID == nil
        
        Logger.subscription.info("[ProductionSubscriptionDebug] Using external ID: \(externalID) (new: \(isNewAccount))")
        
        // Direct purchase bypassing AppStorePurchaseFlow
        guard let manager = AppDependencyProvider.shared.subscriptionManagerV2 else {
            Logger.subscription.error("[ProductionSubscriptionDebug] Subscription manager not available")
            return
        }
        let result = await manager.storePurchaseManager().purchaseSubscription(with: identifier, externalID: externalID)

        switch result {
        case .success(let transactionJWS):
            statusMessage = "✅ Purchase successful! Transaction: \(transactionJWS.prefix(50))..."
            isError = false
            let accountStatus = isNewAccount ? "NEW account created" : "Attached to EXISTING account"
            alertMessage = "Purchase successful! \(accountStatus)\n\nTransaction JWS received. You may need to complete the backend validation separately.\n\nExternal ID: \(externalID)"
            showAlert = true
            
            // Store the external ID for future purchases if this was a new account
            if isNewAccount {
                existingExternalID = externalID
                Logger.subscription.info("[ProductionSubscriptionDebug] Stored new external ID for future purchases: \(externalID)")
            }
            
            Logger.subscription.info("[ProductionSubscriptionDebug] Purchase successful: \(identifier)")
            
        case .failure(let error):
            statusMessage = "❌ Purchase failed: \(error.localizedDescription)"
            isError = true
            alertMessage = "Purchase failed:\n\n\(error.localizedDescription)\n\nProduct: \(identifier)\nExternal ID: \(externalID)"
            showAlert = true
            
            Logger.subscription.error("[ProductionSubscriptionDebug] Purchase failed: \(error.localizedDescription)")
        }
        
        isLoading = false
    }
}
