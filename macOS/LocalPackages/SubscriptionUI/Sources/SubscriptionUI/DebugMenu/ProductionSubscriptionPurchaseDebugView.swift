//
//  ProductionSubscriptionPurchaseDebugView.swift
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
import AppKit
import SwiftUI
import Subscription
import OSLog

/// Closure type for handling subscription selection through the user script handler
/// Parameters: (productId: String, changeType: String?) where changeType is "upgrade", "downgrade", or nil for new purchase
public typealias SubscriptionSelectionHandler = (String, String?) async -> Void

@available(macOS 12.0, *)
public struct ProductionSubscriptionPurchaseDebugView: View {
    @StateObject private var viewModel: ProductionSubscriptionPurchaseViewModel
    let dismissAction: () -> Void

    public init(subscriptionManager: SubscriptionManagerV2,
                subscriptionSelectionHandler: SubscriptionSelectionHandler? = nil,
                dismissAction: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: ProductionSubscriptionPurchaseViewModel(
            subscriptionManager: subscriptionManager,
            subscriptionSelectionHandler: subscriptionSelectionHandler
        ))
        self.dismissAction = dismissAction
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    accountSection
                    currentSubscriptionsSection
                    availableSubscriptionsSection
                    statusSection
                }
                .padding()
            }
            .frame(minWidth: 500, minHeight: 400)
            Divider()
            HStack {
                Spacer()
                Button(UserText.cancelButtonTitle) {
                    dismissAction()
                }
                .keyboardShortcut(.cancelAction)
                .padding()
            }
        }
        .navigationTitle("Change Tier")
        .onAppear {
            Task {
                await viewModel.loadExistingExternalID()
                await viewModel.loadPurchasedProductIDs()
                await viewModel.loadAvailableProducts()
            }
        }
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: "Account")
                .font(.headline)
            if viewModel.isLoadingExternalID {
                Text(verbatim: "Checking for existing account...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else if let externalID = viewModel.existingExternalID {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "Will attach to EXISTING account")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                    Text(verbatim: "External ID: \(externalID)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "Will create NEW account")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                    Text(verbatim: "No existing subscription found")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var currentSubscriptionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: "Current Subscriptions")
                .font(.headline)
            if let productIDs = viewModel.purchasedProductIDs, !productIDs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(productIDs, id: \.self) { productID in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: viewModel.displayName(for: productID))
                                .font(.subheadline)
                            Text(verbatim: productID)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } else {
                Text(verbatim: "No active subscriptions")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var availableSubscriptionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: "Available Products")
                .font(.headline)
            if viewModel.isLoadingProducts {
                Text(verbatim: "Loading available products...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else if viewModel.availableSubscriptions.isEmpty {
                Text(verbatim: "No subscriptions available")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.availableSubscriptions, id: \.self) { identifier in
                        subscriptionRow(identifier: identifier)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        if let message = viewModel.statusMessage {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: "Status")
                    .font(.headline)
                Text(verbatim: message)
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
                    Text(verbatim: viewModel.displayName(for: identifier))
                        .font(.body)
                    Text(verbatim: identifier)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
        }
        .disabled(viewModel.isLoading || viewModel.isLoadingExternalID || viewModel.isLoadingProducts)
    }
}

@available(macOS 12.0, *)
public final class ProductionSubscriptionPurchaseViewController: NSViewController {

    private let subscriptionManager: SubscriptionManagerV2
    private let subscriptionSelectionHandler: SubscriptionSelectionHandler?

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public init(subscriptionManager: SubscriptionManagerV2,
                subscriptionSelectionHandler: SubscriptionSelectionHandler? = nil) {
        self.subscriptionManager = subscriptionManager
        self.subscriptionSelectionHandler = subscriptionSelectionHandler
        super.init(nibName: nil, bundle: nil)
    }

    public override func loadView() {
        let purchaseView = ProductionSubscriptionPurchaseDebugView(
            subscriptionManager: subscriptionManager,
            subscriptionSelectionHandler: subscriptionSelectionHandler,
            dismissAction: { [weak self] in
                guard let self = self else { return }
                self.presentingViewController?.dismiss(self)
            }
        )
        let hostingView = NSHostingView(rootView: purchaseView)
        view = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 500))
        hostingView.frame = view.bounds
        hostingView.autoresizingMask = [.height, .width]
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        view.addSubview(hostingView)
    }
}

@available(macOS 12.0, *)
@MainActor
final class ProductionSubscriptionPurchaseViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var statusMessage: String?
    @Published var isError = false
    @Published var existingExternalID: String?
    @Published var isLoadingExternalID = true
    @Published var purchasedProductIDs: [String]?
    @Published var availableSubscriptions: [String] = []
    @Published var isLoadingProducts = true

    private let subscriptionManager: SubscriptionManagerV2
    private let subscriptionSelectionHandler: SubscriptionSelectionHandler?

    init(subscriptionManager: SubscriptionManagerV2,
         subscriptionSelectionHandler: SubscriptionSelectionHandler? = nil) {
        self.subscriptionManager = subscriptionManager
        self.subscriptionSelectionHandler = subscriptionSelectionHandler
    }

    func loadExistingExternalID() async {
        isLoadingExternalID = true
        do {
            // Try to get existing external ID from authenticated account
            let tokenContainer = try await subscriptionManager.getTokenContainer(policy: .local)
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
        let productIDs = subscriptionManager.storePurchaseManager().purchasedProductIDs
        purchasedProductIDs = productIDs
        Logger.subscription.info("[ProductionSubscriptionDebug] Found \(productIDs.count) purchased product(s): \(productIDs)")
    }

    func loadAvailableProducts() async {
        isLoadingProducts = true

        guard let defaultManager = subscriptionManager.storePurchaseManager() as? DefaultStorePurchaseManagerV2 else {
            Logger.subscription.error("[ProductionSubscriptionDebug] Could not cast to DefaultStorePurchaseManagerV2")
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

        // Determine if this is a tier change or new purchase
        let isTierChange = existingExternalID != nil && !(purchasedProductIDs?.isEmpty ?? true)
        let changeType: String? = isTierChange ? "upgrade" : nil

        if let handler = subscriptionSelectionHandler {
            // Use the subscription selection handler (calls subscriptionChangeSelected or subscriptionSelected)
            // The handler shows its own UI (progress view, alerts) so we just call it and refresh
            let actionType = isTierChange ? "tier change" : "purchase"
            statusMessage = "Starting \(actionType) for \(displayName(for: identifier))..."
            Logger.subscription.info("[ProductionSubscriptionDebug] Using subscriptionSelectionHandler for \(actionType): \(identifier)")

            let previousProductIDs = purchasedProductIDs ?? []
            await handler(identifier, changeType)

            // Refresh purchased product IDs after handler completes
            await loadPurchasedProductIDs()
            let currentProductIDs = purchasedProductIDs ?? []

            // Check if subscription changed to show status
            if currentProductIDs.contains(identifier) && !previousProductIDs.contains(identifier) {
                statusMessage = "✅ \(actionType.capitalized) completed for \(displayName(for: identifier))"
                isError = false
            } else if currentProductIDs != previousProductIDs {
                statusMessage = "✅ Subscription updated"
                isError = false
            } else {
                // No change detected - could be cancelled or failed (handler shows its own alert for failures)
                statusMessage = nil
            }
        } else {
            // Fallback: Direct purchase bypassing the handler
            statusMessage = "Starting purchase for \(displayName(for: identifier))..."

            // Use existing external ID if available, otherwise generate new
            let externalID = existingExternalID ?? UUID().uuidString
            let isNewAccount = existingExternalID == nil
            Logger.subscription.info("[ProductionSubscriptionDebug] Using external ID: \(externalID) (new: \(isNewAccount))")

            // Direct purchase bypassing AppStorePurchaseFlow
            let result = await subscriptionManager.storePurchaseManager().purchaseSubscription(with: identifier, externalID: externalID, includeProTier: true)

            switch result {
            case .success:
                statusMessage = "✅ Purchase successful!"
                isError = false

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
        }
        isLoading = false
    }
}
