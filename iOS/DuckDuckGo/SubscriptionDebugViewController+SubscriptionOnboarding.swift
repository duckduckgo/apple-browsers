//
//  SubscriptionDebugViewController+SubscriptionOnboarding.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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
import SwiftUI
import Subscription
import Persistence
import UIComponents

extension SubscriptionDebugViewController {

    enum OnboardingRows: Int, CaseIterable {
        case resetProgress
        case expireSetupCard
    }

    /// Launches the flow using whatever's currently set in "Onboarding — Configure Mock Flow" below
    enum OnboardingMockRows: Int, CaseIterable {
        case launchFullFlow
        case launchResumeFlow
    }

    /// Inputs for the Mock Flow launch above
    enum OnboardingMockConfigRows: Int, CaseIterable {
        case forcedTrialLength
        case completedVPN
        case completedWidget
        case completedIDTR
        case completedDuckAI
        case completedPIR
        case entitledVPN
        case entitledIDTR
        case entitledIDTRGlobal
        case entitledDuckAI
        case entitledPIR
        case pirAvailable
    }

    enum OnboardingSubflowRows: Int, CaseIterable {
        case orderConfirmation
        case welcome
        case vpn
        case vpnWidget
        case idtr
        case duckAI
        case pir
        case progress
        case progressComplete
        case tapAllowHint
    }

    // MARK: - Cell configuration

    func configureOnboardingCell(_ cell: UITableViewCell, at indexPath: IndexPath) {
        switch OnboardingRows(rawValue: indexPath.row) {
        case .resetProgress:
            cell.textLabel?.text = "Reset Onboarding Progress"
            cell.accessoryType = .none
        case .expireSetupCard:
            cell.textLabel?.text = "Age Setup Card Past 14 Days"
            cell.accessoryType = .none
        case .none:
            break
        }
    }

    func configureOnboardingMockCell(_ cell: UITableViewCell, at indexPath: IndexPath) {
        switch OnboardingMockRows(rawValue: indexPath.row) {
        case .launchFullFlow:
            cell.textLabel?.text = "Launch Full Flow"
            cell.accessoryType = .disclosureIndicator
        case .launchResumeFlow:
            cell.textLabel?.text = "Launch Resume Flow"
            cell.accessoryType = .disclosureIndicator
        case .none:
            break
        }
    }

    func configureOnboardingMockConfigCell(_ cell: UITableViewCell, at indexPath: IndexPath) {
        switch OnboardingMockConfigRows(rawValue: indexPath.row) {
        case .forcedTrialLength:
            cell.textLabel?.text = "Force Trial Length"
            cell.detailTextLabel?.text = "\(mockForcedTrialLengthDays.map { "\($0) days" } ?? "Off")"
            cell.accessoryType = .none
        case .completedVPN:
            cell.textLabel?.text = "Completed: VPN"
            cell.accessoryType = mockCompletedItems.contains(.vpn) ? .checkmark : .none
        case .completedWidget:
            cell.textLabel?.text = "Completed: VPN Widget"
            cell.accessoryType = mockCompletedItems.contains(.vpnWidget) ? .checkmark : .none
        case .completedIDTR:
            cell.textLabel?.text = "Completed: IDTR"
            cell.accessoryType = mockCompletedItems.contains(.idtr) ? .checkmark : .none
        case .completedDuckAI:
            cell.textLabel?.text = "Completed: Duck.ai"
            cell.accessoryType = mockCompletedItems.contains(.duckAI) ? .checkmark : .none
        case .completedPIR:
            cell.textLabel?.text = "Completed: PIR"
            cell.accessoryType = mockCompletedItems.contains(.pir) ? .checkmark : .none
        case .entitledVPN:
            cell.textLabel?.text = "Entitled: Network Protection (VPN)"
            cell.accessoryType = mockNetworkProtection ? .checkmark : .none
        case .entitledIDTR:
            cell.textLabel?.text = "Entitled: Identity Theft Restoration"
            cell.accessoryType = mockIdentityTheftRestoration ? .checkmark : .none
        case .entitledIDTRGlobal:
            cell.textLabel?.text = "Entitled: Identity Theft Restoration (Global)"
            cell.accessoryType = mockIdentityTheftRestorationGlobal ? .checkmark : .none
        case .entitledDuckAI:
            cell.textLabel?.text = "Entitled: Duck.ai"
            cell.accessoryType = mockPaidAIChat ? .checkmark : .none
        case .entitledPIR:
            cell.textLabel?.text = "Entitled: Data Broker Protection (PIR)"
            cell.accessoryType = mockDataBrokerProtection ? .checkmark : .none
        case .pirAvailable:
            cell.textLabel?.text = "PIR Available (flag/locale/provider)"
            cell.accessoryType = mockIsPIRAvailable ? .checkmark : .none
        case .none:
            break
        }
    }

    func configureOnboardingSubflowCell(_ cell: UITableViewCell, at indexPath: IndexPath) {
        switch OnboardingSubflowRows(rawValue: indexPath.row) {
        case .orderConfirmation:
            cell.textLabel?.text = "Order Confirmation"
            cell.accessoryType = .disclosureIndicator
        case .welcome:
            cell.textLabel?.text = "Welcome"
            cell.accessoryType = .disclosureIndicator
        case .vpn:
            cell.textLabel?.text = "VPN"
            cell.accessoryType = .disclosureIndicator
        case .vpnWidget:
            cell.textLabel?.text = "VPN Widget (+ VPN Tips)"
            cell.accessoryType = .disclosureIndicator
        case .idtr:
            cell.textLabel?.text = "Identity Theft Restoration"
            cell.accessoryType = .disclosureIndicator
        case .duckAI:
            cell.textLabel?.text = "Duck.ai"
            cell.accessoryType = .disclosureIndicator
        case .pir:
            cell.textLabel?.text = "Personal Information Removal"
            cell.accessoryType = .disclosureIndicator
        case .progress:
            cell.textLabel?.text = "Progress — Summary (80%)"
            cell.accessoryType = .disclosureIndicator
        case .progressComplete:
            cell.textLabel?.text = "Progress — Completion (100% + confetti)"
            cell.accessoryType = .disclosureIndicator
        case .tapAllowHint:
            cell.textLabel?.text = "Tap Allow Hint Overlay"
            cell.accessoryType = .disclosureIndicator
        case .none:
            break
        }
    }

    // MARK: - Row selection

    func didSelectOnboardingRow(at indexPath: IndexPath) {
        switch OnboardingRows(rawValue: indexPath.row) {
        case .resetProgress: resetOnboardingProgress()
        case .expireSetupCard: expireSetupCardWindow()
        case .none: break
        }
    }

    func didSelectOnboardingMockRow(at indexPath: IndexPath) {
        switch OnboardingMockRows(rawValue: indexPath.row) {
        case .launchFullFlow: showMockOnboardingFlow(entryPoint: .postCheckout)
        case .launchResumeFlow: showMockOnboardingFlow(entryPoint: .subscriptionSettings)
        case .none: break
        }
    }

    func didSelectOnboardingMockConfigRow(at indexPath: IndexPath) {
        switch OnboardingMockConfigRows(rawValue: indexPath.row) {
        case .forcedTrialLength: promptForcedTrialLength(at: indexPath)
        case .completedVPN: toggleMockCompleted(.vpn, at: indexPath)
        case .completedWidget: toggleMockCompleted(.vpnWidget, at: indexPath)
        case .completedIDTR: toggleMockCompleted(.idtr, at: indexPath)
        case .completedDuckAI: toggleMockCompleted(.duckAI, at: indexPath)
        case .completedPIR: toggleMockCompleted(.pir, at: indexPath)
        case .entitledVPN: toggleMock(\.mockNetworkProtection, at: indexPath)
        case .entitledIDTR: toggleMock(\.mockIdentityTheftRestoration, at: indexPath)
        case .entitledIDTRGlobal: toggleMock(\.mockIdentityTheftRestorationGlobal, at: indexPath)
        case .entitledDuckAI: toggleMock(\.mockPaidAIChat, at: indexPath)
        case .entitledPIR: toggleMock(\.mockDataBrokerProtection, at: indexPath)
        case .pirAvailable: toggleMock(\.mockIsPIRAvailable, at: indexPath)
        case .none: break
        }
    }

    func didSelectOnboardingSubflowRow(at indexPath: IndexPath) {
        switch OnboardingSubflowRows(rawValue: indexPath.row) {
        case .orderConfirmation: showOrderConfirmationOnboarding()
        case .welcome: showWelcomeOnboarding()
        case .vpn: showVPNOnboarding()
        case .vpnWidget: showVPNWidgetOnboarding()
        case .idtr: showIDTROnboarding()
        case .duckAI: showDuckAIOnboarding()
        case .pir: showPIROnboarding()
        case .progress: showProgressOnboarding(completedItems: [.vpn, .vpnWidget, .vpnTips, .idtr, .duckAI])
        case .progressComplete: showProgressOnboarding(completedItems: Set(SubscriptionOnboardingChecklistItem.allCases))
        case .tapAllowHint: showTapAllowHintPlayground()
        case .none: break
        }
    }

    // MARK: - Standalone subflow screens

    private func showOrderConfirmationOnboarding() {
        let hostingController = UIHostingController(
            rootView: SubscriptionOnboardingOrderConfirmationView(
                viewModel: SubscriptionOnboardingOrderConfirmationViewModel(
                    onNext: { [weak self] in self?.dismiss(animated: true) }),
                navigationButton: .close({ [weak self] in self?.dismiss(animated: true) }))
                .subscriptionOnboardingNavigationContainer())
        present(hostingController, animated: true)
    }

    private func showIDTROnboarding() {
        showProtectionOverviewOnboarding(content: .idtr)
    }

    /// The real "start PIR" hand-off needs the Data Broker Protection view-controller provider, which lives
    /// on `DBPService` and reaches the flow as `SubscriptionOnboardingFlowViewModel.subscriptionSettings`'s
    /// `pirScreen`. The debug menu has no handle on it, so this standalone row's CTA just dismisses.
    private func showPIROnboarding() {
        showProtectionOverviewOnboarding(content: .pir)
    }

    private func showProtectionOverviewOnboarding(content: SubscriptionOnboardingInfoContent) {
        let hostingController = UIHostingController(
            rootView: SubscriptionOnboardingProtectionOverviewView(
                content: content,
                navigationButton: .close({ [weak self] in self?.dismiss(animated: true) }),
                onNext: { [weak self] in self?.dismiss(animated: true) })
                .subscriptionOnboardingNavigationContainer())
        present(hostingController, animated: true)
    }

    private func showProgressOnboarding(completedItems: Set<SubscriptionOnboardingChecklistItem>) {
        let hostingController = UIHostingController(
            rootView: SubscriptionOnboardingProgressView(
                progress: SubscriptionOnboardingProgress(completedItems: completedItems),
                navigationButton: .close({ [weak self] in self?.dismiss(animated: true) }),
                onSelectItem: { _ in },
                onNext: { [weak self] in self?.dismiss(animated: true) })
                .subscriptionOnboardingNavigationContainer()
                .graphicLottieRenderer(.app))
        present(hostingController, animated: true)
    }

    private func showWelcomeOnboarding() {
        let hostingController = UIHostingController(
            rootView: SubscriptionOnboardingWelcomeView(
                navigationButton: .close({ [weak self] in self?.dismiss(animated: true) }),
                onNext: { [weak self] in self?.dismiss(animated: true) })
                .subscriptionOnboardingNavigationContainer())
        present(hostingController, animated: true)
    }

    private func showVPNOnboarding() {
        let hostingController = UIHostingController(
            rootView: SubscriptionOnboardingVPNActivationView(
                viewModel: SubscriptionOnboardingVPNActivationViewModel(
                    prefetcher: SubscriptionOnboardingPrefetcher(),
                    onNext: { [weak self] in self?.dismiss(animated: true) }),
                navigationButton: .close({ [weak self] in self?.dismiss(animated: true) }))
                .subscriptionOnboardingNavigationContainer()
                .graphicLottieRenderer(.app))
        present(hostingController, animated: true)
    }

    private func showVPNWidgetOnboarding() {
        let hostingController = UIHostingController(
            rootView: VPNWidgetAndTipsDebugFlow(onFinish: { [weak self] in self?.dismiss(animated: true) })
                .subscriptionOnboardingNavigationContainer())
        present(hostingController, animated: true)
    }

    private func showDuckAIOnboarding() {
        let hostingController = UIHostingController(
            rootView: SubscriptionOnboardingDuckAIView(
                viewModel: SubscriptionOnboardingDuckAIViewModel(
                    prefetcher: SubscriptionOnboardingPrefetcher(),
                    onNext: { [weak self] in self?.dismiss(animated: true) },
                    onRequestChat: { modelID in
                        SubscriptionOnboardingDuckAIChatLauncher().launch(modelID: modelID)
                    }),
                navigationButton: .close({ [weak self] in self?.dismiss(animated: true) }),
                progress: SubscriptionOnboardingProgress(completedItems: [.vpn, .vpnWidget, .vpnTips, .idtr]))
                .subscriptionOnboardingNavigationContainer()
                .graphicLottieRenderer(.app))
        present(hostingController, animated: true)
    }

    private func showTapAllowHintPlayground() {
        let hostingController = UIHostingController(
            rootView: TapAllowHintOverlayPlaygroundView(onClose: { [weak self] in self?.dismiss(animated: true) }))
        hostingController.modalPresentationStyle = .overFullScreen
        hostingController.view.backgroundColor = .clear
        present(hostingController, animated: true)
    }

    // MARK: - Mock full/resume flow

    /// Uses the designated `init` directly — the real `.postCheckout`/`.subscriptionSettings` factories always
    /// fetch this device's actual entitlement, which would defeat the mock toggles.
    private func showMockOnboardingFlow(entryPoint: SubscriptionOnboardingEntryPoint) {
        let entitlement = EntitlementStatus(networkProtection: mockNetworkProtection,
                                            dataBrokerProtection: mockDataBrokerProtection,
                                            identityTheftRestoration: mockIdentityTheftRestoration,
                                            identityTheftRestorationGlobal: mockIdentityTheftRestorationGlobal,
                                            paidAIChat: mockPaidAIChat)
        let flow = SubscriptionOnboardingFlowViewModel(
            entryPoint: entryPoint,
            progress: SubscriptionOnboardingProgress(completedItems: mockCompletedItems,
                                                     isPIRAvailable: mockIsPIRAvailable,
                                                     entitlement: entitlement),
            onFinish: { [weak self] in
                self?.dismiss(animated: true)
                guard entryPoint == .postCheckout else { return }
                NotificationCenter.default.post(name: .settingsDeepLinkNotification,
                                                object: SettingsViewModel.SettingsDeepLinkSection.subscriptionSettings)
            },
            // No Data Broker Protection provider here, so PIR falls back to the move-to-desktop screen.
            pirScreen: { SubscriptionPIRMoveToDesktopView() })
        let root = SubscriptionOnboardingLauncher.launchForDebug(flow: flow, forcedTrialLengthDays: mockForcedTrialLengthDays)
        present(UIHostingController(rootView: root), animated: true)
    }

    private func toggleMock(_ flag: ReferenceWritableKeyPath<SubscriptionDebugViewController, Bool>, at indexPath: IndexPath) {
        self[keyPath: flag].toggle()
        tableView.reloadRows(at: [indexPath], with: .none)
    }

    private func toggleMockCompleted(_ item: SubscriptionOnboardingChecklistItem, at indexPath: IndexPath) {
        if mockCompletedItems.contains(item) {
            mockCompletedItems.remove(item)
        } else {
            mockCompletedItems.insert(item)
        }
        tableView.reloadRows(at: [indexPath], with: .none)
    }

    private func promptForcedTrialLength(at indexPath: IndexPath) {
        let alert = UIAlertController(title: "Force Trial Length",
                                      message: "Days shown on the Order Confirmation free-trial card when using Launch Full Flow. Valid values between 1 and 10.",
                                      preferredStyle: .alert)
        weak var daysTextField: UITextField?
        alert.addTextField { field in
            field.keyboardType = .numberPad
            field.placeholder = "Days"
            field.text = self.mockForcedTrialLengthDays.map(String.init)
            daysTextField = field
        }
        alert.addAction(UIAlertAction(title: "Set", style: .default) { [weak self] _ in
            guard let self else { return }
            let days = Int(daysTextField?.text ?? "")
            self.mockForcedTrialLengthDays = (days ?? 0) > 0 ? days : nil
            self.tableView.reloadRows(at: [indexPath], with: .none)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    // MARK: - On-device progress utilities

    private func resetOnboardingProgress() {
        guard let keyValueStore else {
            showAlert(title: "Failed to reset onboarding progress")
            return
        }
        var store = SubscriptionOnboardingProgressPersistor(keyValueStore: keyValueStore)
        store.completedItems = []
        store.cardFirstShownDate = nil
        store.fullyCompletedAt = nil
        store.completionViewCount = 0
        showAlert(title: "Onboarding progress reset")
    }

    /// Backdates the card's first display so its 14-day window has already closed. The session latch is
    /// process-scoped, so a relaunch is still needed to test the "hidden after completion" rule.
    private func expireSetupCardWindow() {
        guard let keyValueStore else {
            showAlert(title: "Failed to age setup card")
            return
        }
        var store = SubscriptionOnboardingProgressPersistor(keyValueStore: keyValueStore)
        store.cardFirstShownDate = Date().addingTimeInterval(-TimeInterval.days(15))
        showAlert(title: "Setup card aged past 14 days")
    }
}

/// Chains widget-education into tips for the debug menu, since there's no flow view model to push through.
private struct VPNWidgetAndTipsDebugFlow: View {
    let onFinish: () -> Void

    @State private var isShowingTips = false

    var body: some View {
        SubscriptionOnboardingVPNWidgetEducationView(
            navigationButton: .close(onFinish),
            onNext: { isShowingTips = true })
            .background(
                NavigationLink(isActive: $isShowingTips) {
                    SubscriptionOnboardingVPNTipsView(onNext: onFinish)
                } label: { EmptyView() }
            )
    }
}
