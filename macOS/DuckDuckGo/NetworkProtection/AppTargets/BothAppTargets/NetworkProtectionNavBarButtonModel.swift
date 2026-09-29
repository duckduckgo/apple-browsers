//
//  NetworkProtectionNavBarButtonModel.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
import Combine
import ConcurrencyExtensions
import Foundation
import NetworkProtectionIPC
import NetworkProtectionUI
import VPN

/// Model for managing the NetP button in the Nav Bar.
///
final class NetworkProtectionNavBarButtonModel: NSObject, ObservableObject {

    private let networkProtectionStatusReporter: NetworkProtectionStatusReporter
    private var status: VPN.ConnectionStatus = .default
    private let popoverManager: NetPPopoverManager
    private let vpnUpsellToolbarButtonPromoDelegate: VPNUpsellToolbarButtonPromoDelegate
    private let vpnUpsellDotBadgePromoDelegate: VPNUpsellDotBadgePromoDelegate

    // MARK: - Subscriptions

    private var cancellables = Set<AnyCancellable>()

    // MARK: - VPN

    private let vpnGatekeeper: VPNFeatureGatekeeper
    private let iconPublisher: NetworkProtectionIconPublisher
    private var iconPublisherCancellable: AnyCancellable?

    // MARK: - Button appearance

    private let pinningManager: PinningManager

    @Published
    private(set) var showVPNButton = false {
        didSet {
            shortcutTitle = pinningManager.shortcutTitle(for: .networkProtection)
        }
    }

    @Published
    private(set) var shortcutTitle: String

    @Published
    private(set) var buttonImage: NSImage?

    var isPinned: Bool {
        pinningManager.isPinned(.networkProtection)
    }

    // MARK: - NetP State

    private var isHavingConnectivityIssues = false

    // MARK: - Upsell

    @Published
    private(set) var shouldShowUpsell = false

    @Published
    private(set) var shouldShowNotificationDot = false

    // MARK: - Initialization

    init(popoverManager: NetPPopoverManager,
         pinningManager: PinningManager,
         vpnGatekeeper: VPNFeatureGatekeeper,
         statusReporter: NetworkProtectionStatusReporter,
         themeManager: ThemeManaging,
         vpnUpsellToolbarButtonPromoDelegate: VPNUpsellToolbarButtonPromoDelegate,
         vpnUpsellDotBadgePromoDelegate: VPNUpsellDotBadgePromoDelegate) {

        let iconsProvider = themeManager.theme.iconsProvider

        self.popoverManager = popoverManager
        self.vpnGatekeeper = vpnGatekeeper
        self.networkProtectionStatusReporter = statusReporter
        self.iconPublisher = NetworkProtectionIconPublisher(statusReporter: networkProtectionStatusReporter, iconProvider: iconsProvider.vpnNavigationIconsProvider)
        self.pinningManager = pinningManager
        self.shortcutTitle = pinningManager.shortcutTitle(for: .networkProtection)
        self.vpnUpsellToolbarButtonPromoDelegate = vpnUpsellToolbarButtonPromoDelegate
        self.vpnUpsellDotBadgePromoDelegate = vpnUpsellDotBadgePromoDelegate

        isHavingConnectivityIssues = networkProtectionStatusReporter.connectivityIssuesObserver.recentValue
        buttonImage = .image(for: iconPublisher.icon)

        super.init()

        setupSubscriptions()
    }

    // MARK: - Subscriptions

    private func setupSubscriptions() {
        setupIconSubscription()
        setupStatusSubscription()
        setupInterruptionSubscription()
        setupUpsellSubscription()
    }

    private func setupIconSubscription() {
        iconPublisherCancellable = iconPublisher.$icon
            .receive(on: DispatchQueue.main)
            .sink { [weak self] icon in
                self?.buttonImage = .image(for: icon)!
            }
    }

    private func setupStatusSubscription() {
        networkProtectionStatusReporter.statusObserver.publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self else { return }

                MainActor.assumeMainThread {
                    self.status = status
                    self.updateVisibility()
                }
            }.store(in: &cancellables)
    }

    private func setupInterruptionSubscription() {
        networkProtectionStatusReporter.connectivityIssuesObserver.publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isHavingConnectivityIssues in
                guard let self else { return }

                MainActor.assumeMainThread {
                    self.isHavingConnectivityIssues = isHavingConnectivityIssues
                    self.updateVisibility()
                }
            }
            .store(in: &cancellables)
    }

    private func setupUpsellSubscription() {
        vpnUpsellToolbarButtonPromoDelegate.isShowingPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isShowing in
                guard let self else { return }

                MainActor.assumeMainThread {
                    self.shouldShowUpsell = isShowing
                    self.updateVisibility()
                }
            }
            .store(in: &cancellables)

        // The dot is drawn on the upsell button, so it only shows while both promos are showing.
        Publishers.CombineLatest(vpnUpsellToolbarButtonPromoDelegate.isShowingPublisher,
                                 vpnUpsellDotBadgePromoDelegate.isShowingPublisher)
            .map { $0 && $1 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] shouldShowNotificationDot in
                guard let self else { return }

                MainActor.assumeMainThread {
                    self.shouldShowNotificationDot = shouldShowNotificationDot
                }
            }
            .store(in: &cancellables)
    }

    @MainActor
    func updateVisibility() {
        Task { @MainActor in
            guard !shouldShowUpsell else {
                pinNetworkProtectionToNavBarIfNeverPinnedBefore()
                showVPNButton = true
                return
            }

            guard let canStartVPN = try? await vpnGatekeeper.canStartVPN() else {
                // If there's an error, don't make any changes
                return
            }

            // The promo can be restored while awaiting; unpinning then would silently dismiss the upsell.
            if shouldShowUpsell {
                pinNetworkProtectionToNavBarIfNeverPinnedBefore()
                showVPNButton = true
                return
            }

            if canStartVPN {
                pinNetworkProtectionToNavBarIfNeverPinnedBefore()
            } else {
                pinningManager.unpin(.networkProtection)
                showVPNButton = false
                return
            }

            showVPNButton = isPinned || popoverManager.isShown || isHavingConnectivityIssues
        }
    }

    // MARK: - Pinning

    @objc
    func togglePin() {
        pinningManager.togglePinning(for: .networkProtection)
    }

    /// We want to pin the VPN to the navigation bar the first time it's enabled, and only
    /// if the user hasn't toggled it manually before.
    /// 
    private func pinNetworkProtectionToNavBarIfNeverPinnedBefore() {
        guard !pinningManager.isPinned(.networkProtection),
              !pinningManager.wasManuallyToggled(.networkProtection) else {
            return
        }

        pinningManager.pin(.networkProtection)
    }
}

extension NetworkProtectionNavBarButtonModel: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        updateVisibility()
    }
}
