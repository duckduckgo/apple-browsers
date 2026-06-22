//
//  VPNTipsModel.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import CombineExtensions
import Common
import FoundationExtensions
import VPN
import NetworkProtectionProxy
import os.log
import TipKit
import PixelKit
import VPNAppState
import VPNPixels

@MainActor
public final class VPNTipsModel: ObservableObject {

    static let imageSize = CGSize(width: 32, height: 32)

    @Published
    private(set) var activeSiteInfo: ActiveSiteInfo? {
        didSet {
            guard #available(macOS 14.0, *) else {
                return
            }

            handleActiveSiteInfoChanged(newValue: activeSiteInfo)
        }
    }

    @Published
    private(set) var connectionStatus: ConnectionStatus {
        didSet {
            if #available(macOS 14.0, *) {
                handleConnectionStatusChanged(oldValue: oldValue, newValue: connectionStatus)
            } else {
                refreshStrictRoutingReminder()
            }
        }
    }

    /// Drives the pre-macOS-14 fallback reminder view (macOS 14+ uses TipKit instead). Also set
    /// when the debug force flag is on, so the fallback can be exercised on any OS version.
    @Published
    private(set) var showStrictRoutingFallbackReminder = false

    /// How long the user must have had Strict routing disabled before the reminder first appears,
    /// and the interval at which it recurs afterwards. Overridable from the VPN debug menu.
    // TODO: REVERT BEFORE MERGING — hardcoded to 30s for testing (was 7 * 24 * 60 * 60)
    static let defaultStrictRoutingReminderInterval: TimeInterval = 30

    private let isMenuApp: Bool
    private let vpnAppState: VPNAppState
    private let vpnSettings: VPNSettings
    private let proxySettings: TransparentProxySettings
    private let strictRoutingReminderStore: VPNStrictRoutingReminderStore
    private let strictRoutingReminderFeatureEnabled: Bool
    private let logger: Logger
    private var cancellables = Set<AnyCancellable>()

    public init(statusObserver: ConnectionStatusObserver,
                activeSitePublisher: CurrentValuePublisher<ActiveSiteInfo?, Never>,
                forMenuApp isMenuApp: Bool,
                vpnAppState: VPNAppState,
                vpnSettings: VPNSettings,
                proxySettings: TransparentProxySettings,
                strictRoutingReminderStore: VPNStrictRoutingReminderStore,
                strictRoutingReminderFeatureEnabled: Bool,
                logger: Logger) {

        self.activeSiteInfo = activeSitePublisher.value
        self.connectionStatus = statusObserver.recentValue
        self.isMenuApp = isMenuApp
        self.logger = logger
        self.vpnAppState = vpnAppState
        self.vpnSettings = vpnSettings
        self.proxySettings = proxySettings
        self.strictRoutingReminderStore = strictRoutingReminderStore
        self.strictRoutingReminderFeatureEnabled = strictRoutingReminderFeatureEnabled

        guard !isMenuApp else {
            return
        }

        // The strict-routing reminder runs on all OS versions (TipKit on macOS 14+, a custom
        // fallback view below that), so its subscriptions aren't gated.
        subscribeToConnectionStatusChanges(statusObserver)
        subscribeToEnforceRoutesChanges()

        if #available(macOS 14.0, *) {
            handleActiveSiteInfoChanged(newValue: activeSiteInfo)
            handleConnectionStatusChanged(oldValue: connectionStatus, newValue: connectionStatus)

            subscribeToActiveSiteChanges(activeSitePublisher)
        } else {
            refreshStrictRoutingReminder()
        }
    }

    deinit {
        geoswitchingStatusUpdateTask?.cancel()
        geoswitchingStatusUpdateTask = nil
    }

    var canShowTips: Bool {
        !isMenuApp
    }

    // MARK: - Subscriptions

    private func subscribeToConnectionStatusChanges(_ statusObserver: ConnectionStatusObserver) {
        statusObserver.publisher
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .assign(to: \.connectionStatus, onWeaklyHeld: self)
            .store(in: &cancellables)
    }

    private func subscribeToEnforceRoutesChanges() {
        vpnSettings.enforceRoutesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enforceRoutes in
                guard let self else { return }

                // Anchor the grace period to when Strict routing was first seen disabled, and clear
                // the dates once it's back on so the next time it's disabled starts fresh.
                if enforceRoutes {
                    self.strictRoutingReminderStore.clear()
                } else {
                    self.strictRoutingReminderStore.recordDisabledIfNecessary()
                }

                self.refreshStrictRoutingReminder()
            }
            .store(in: &cancellables)
    }

    @available(macOS 14.0, *)
    private func subscribeToActiveSiteChanges(_ publisher: CurrentValuePublisher<ActiveSiteInfo?, Never>) {

        publisher
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .assign(to: \.activeSiteInfo, onWeaklyHeld: self)
            .store(in: &cancellables)
    }

    // MARK: - Tips

    let autoconnectTip = VPNAutoconnectTip()
    let domainExclusionsTip = VPNDomainExclusionsTip()
    let geoswitchingTip = VPNGeoswitchingTip()
    let strictRoutingTip = VPNStrictRoutingTip()

    var geoswitchingStatusUpdateTask: Task<Void, Never>?

    @available(macOS 14.0, *)
    var canShowStrictRoutingTip: Bool {
        canShowTips
    }

    @available(macOS 14.0, *)
    var canShowDomainExclusionsTip: Bool {
        guard canShowTips else {
            return false
        }

        // If the proxy is available, we can show this tip after the geoswitchin tip
        // Otherwise we can't show this tip
        if vpnAppState.isUsingSystemExtension,
           case .invalidated = geoswitchingTip.status {

            return true
        }

        return false
    }

    @available(macOS 14.0, *)
    var canShowAutoconnectTip: Bool {
        guard canShowTips else {
            return false
        }

        // If the proxy is available, we need to wait until the domain exclusions tip was shown.
        // If the proxy is not available, we can show this tip after the geoswitchin tip
        if vpnAppState.isUsingSystemExtension,
           case .invalidated = domainExclusionsTip.status {

            return true
        } else if !vpnAppState.isUsingSystemExtension,
           case .invalidated = geoswitchingTip.status {

            return true
        }

        return false
    }

    // MARK: - Tip Action handling

    @available(macOS 14.0, *)
    func autoconnectTipActionHandler(_ action: Tip.Action) {
        if action.id == VPNAutoconnectTip.ActionIdentifiers.enable.rawValue {
            vpnSettings.connectOnLogin = true

            autoconnectTip.invalidate(reason: .actionPerformed)
        }
    }

    @available(macOS 14.0, *)
    func strictRoutingTipActionHandler(_ action: Tip.Action) {
        if action.id == VPNStrictRoutingTip.ActionIdentifiers.enable.rawValue {
            // Re-enabling routes the change through the settings publisher, which restarts the
            // tunnel and clears the reminder dates.
            vpnSettings.enforceRoutes = true

            strictRoutingTip.invalidate(reason: .actionPerformed)
        }
    }

    // MARK: - Strict Routing Reminder

    /// Recomputes whether the reminder is currently due. The tip first appears only once Strict
    /// routing has been disabled for the interval, then recurs at the same interval until the user
    /// turns it back on (which clears the dates) or dismisses the tip (which invalidates it).
    private func refreshStrictRoutingReminder() {
        guard !isMenuApp else { return }

        guard strictRoutingReminderFeatureEnabled else {
            showStrictRoutingFallbackReminder = false
            if #available(macOS 14.0, *) {
                VPNStrictRoutingTip.shouldShow = false
            }
            return
        }

        let interval = strictRoutingReminderStore.overriddenInterval ?? Self.defaultStrictRoutingReminderInterval

        // Strict routing only affects traffic while the tunnel is up, so the reminder is only
        // relevant — and its "traffic may leak" message only accurate — when the VPN is connected.
        // It also only recurs once the user has had it off for a full interval since last shown.
        let isDue: Bool
        if case .connected = connectionStatus,
           !vpnSettings.enforceRoutes,
           let secondsSinceDisabled = strictRoutingReminderStore.secondsSinceDisabled(),
           secondsSinceDisabled >= interval {

            let shownRecently = (strictRoutingReminderStore.secondsSinceReminderShown() ?? .greatestFiniteMagnitude) < interval
            isDue = !shownRecently
        } else {
            isDue = false
        }

        guard #available(macOS 14.0, *) else {
            // No TipKit below macOS 14, so the custom fallback view is the only option.
            showStrictRoutingFallbackReminder = isDue
            return
        }

        guard isDue,
              let secondsSinceDisabled = strictRoutingReminderStore.secondsSinceDisabled() else {
            showStrictRoutingFallbackReminder = false
            VPNStrictRoutingTip.shouldShow = false
            return
        }

        // Defer to the onboarding tips: only surface the reminder when none of the others are
        // currently showing, so it never stacks on top of them.
        let otherTipAvailable = [autoconnectTip.status, domainExclusionsTip.status, geoswitchingTip.status].contains {
            if case .available = $0 { return true }
            return false
        }
        guard !otherTipAvailable else {
            showStrictRoutingFallbackReminder = false
            VPNStrictRoutingTip.shouldShow = false
            return
        }

        // Debug override: render the pre-macOS-14 fallback view in place of the TipKit tip under the
        // same showing conditions, so it can be previewed on a modern OS.
        if strictRoutingReminderStore.forceFallbackReminder {
            VPNStrictRoutingTip.shouldShow = false
            showStrictRoutingFallbackReminder = true
            return
        }

        showStrictRoutingFallbackReminder = false

        // Rotate the tip's identity each interval so a previous permanent dismissal (the X button)
        // doesn't suppress the next recurrence — TipKit treats each interval as a brand-new tip.
        VPNStrictRoutingTip.currentInterval = Int(secondsSinceDisabled / interval)
        VPNStrictRoutingTip.shouldShow = true
    }

    // MARK: - Handle Refreshing

    @available(macOS 14.0, *)
    private func handleActiveSiteInfoChanged(newValue: ActiveSiteInfo?) {
        guard !isMenuApp else { return }
        return VPNDomainExclusionsTip.hasActiveSite = (activeSiteInfo != nil)
    }

    @available(macOS 14.0, *)
    private func handleConnectionStatusChanged(oldValue: ConnectionStatus, newValue: ConnectionStatus) {
        guard !isMenuApp else { return }
        switch newValue {
        case .connected:
            if case oldValue = .connecting {
                handleTipDistanceConditionsCheckpoint()
            }

            VPNGeoswitchingTip.vpnEnabledOnce = true
            VPNAutoconnectTip.vpnEnabled = true
            VPNDomainExclusionsTip.vpnEnabled = true
        default:
            VPNAutoconnectTip.vpnEnabled = false
            VPNDomainExclusionsTip.vpnEnabled = false
        }

        // The reminder is gated on the VPN being connected, so re-evaluate it as the status changes.
        refreshStrictRoutingReminder()
    }

    @available(macOS 14.0, *)
    private func handleTipDistanceConditionsCheckpoint() {
        if case .invalidated = geoswitchingTip.status {
            VPNDomainExclusionsTip.isDistancedFromPreviousTip = true
        }

        if case .invalidated = domainExclusionsTip.status {
            VPNAutoconnectTip.isDistancedFromPreviousTip = true
        }
    }

    // MARK: - UI Events

    @available(macOS 14.0, *)
    func handleAutoconnectTipInvalidated(_ reason: Tip.InvalidationReason) {
        switch reason {
        case .actionPerformed:
            PixelKit.fire(VPNTipPixel.autoconnectTip(step: .actioned))
        default:
            PixelKit.fire(VPNTipPixel.autoconnectTip(step: .dismissed))
        }
    }

    @available(macOS 14.0, *)
    func handleDomainExclusionTipInvalidated(_ reason: Tip.InvalidationReason) {
        switch reason {
        case .actionPerformed:
            PixelKit.fire(VPNTipPixel.domainExclusionsTip(step: .actioned))
        default:
            PixelKit.fire(VPNTipPixel.domainExclusionsTip(step: .dismissed))
        }
    }

    @available(macOS 14.0, *)
    func handleGeoswitchingTipInvalidated(_ reason: Tip.InvalidationReason) {
        switch reason {
        case .actionPerformed:
            PixelKit.fire(VPNTipPixel.geoswitchingTip(step: .actioned))
        default:
            PixelKit.fire(VPNTipPixel.geoswitchingTip(step: .dismissed))
        }
    }

    @available(macOS 14.0, *)
    func handleStrictRoutingTipInvalidated(_ reason: Tip.InvalidationReason) {
        switch reason {
        case .actionPerformed:
            PixelKit.fire(VPNTipPixel.strictRoutingTip(step: .actioned))
        default:
            // Dismissing with the close button mutes the reminder for the current interval; it
            // recurs at the next one. The tip otherwise stays visible until the user acts on it.
            strictRoutingReminderStore.recordReminderShown()

            PixelKit.fire(VPNTipPixel.strictRoutingTip(step: .dismissed))
        }
    }

    // MARK: - Strict Routing Fallback (pre-macOS 14)

    /// Re-evaluates the reminder when the tunnel controller appears. Used on the pre-macOS-14 path;
    /// macOS 14+ goes through `handleTunnelControllerAppear`, which also drives the TipKit tips.
    func handleStrictRoutingReminderViewAppear() {
        refreshStrictRoutingReminder()
    }

    func handleStrictRoutingFallbackShown() {
        guard !isMenuApp else { return }

        PixelKit.fire(VPNTipPixel.strictRoutingTip(step: .shown))
    }

    func handleStrictRoutingFallbackEnable() {
        guard !isMenuApp else { return }

        // Re-enabling routes the change through the settings publisher, which restarts the tunnel
        // and clears the reminder dates.
        vpnSettings.enforceRoutes = true
        showStrictRoutingFallbackReminder = false

        PixelKit.fire(VPNTipPixel.strictRoutingTip(step: .actioned))
    }

    func handleStrictRoutingFallbackDismiss() {
        guard !isMenuApp else { return }

        // Mute for the current interval; it recurs at the next interval just like the TipKit tip.
        strictRoutingReminderStore.recordReminderShown()
        showStrictRoutingFallbackReminder = false

        PixelKit.fire(VPNTipPixel.strictRoutingTip(step: .dismissed))
    }

    @available(macOS 14.0, *)
    func handleLocationsShown() {
        guard !isMenuApp else { return }
        geoswitchingTip.invalidate(reason: .actionPerformed)
    }

    @available(macOS 14.0, *)
    func handleSiteExcluded() {
        guard !isMenuApp else { return }
        domainExclusionsTip.invalidate(reason: .actionPerformed)
    }

    @available(macOS 14.0, *)
    func handleTunnelControllerAppear() {
        guard !isMenuApp else { return }

        handleTipDistanceConditionsCheckpoint()
        refreshStrictRoutingReminder()
    }

    @available(macOS 14.0, *)
    func handleTunnelControllerDisappear() {
        guard !isMenuApp else { return }

        if case .available = autoconnectTip.status {
            PixelKit.fire(VPNTipPixel.autoconnectTip(step: .ignored))
        }

        if case .available = domainExclusionsTip.status {
            PixelKit.fire(VPNTipPixel.domainExclusionsTip(step: .ignored))
        }

        if case .available = geoswitchingTip.status {
            PixelKit.fire(VPNTipPixel.geoswitchingTip(step: .ignored))
        }

        if case .available = strictRoutingTip.status {
            PixelKit.fire(VPNTipPixel.strictRoutingTip(step: .ignored))
        }
    }

    @available(macOS 14.0, *)
    func handleAutoconnectionTipShown() {
        guard !isMenuApp else { return }

        PixelKit.fire(VPNTipPixel.autoconnectTip(step: .shown))
    }

    @available(macOS 14.0, *)
    func handleDomainExclusionsTipShown() {
        guard !isMenuApp else { return }

        PixelKit.fire(VPNTipPixel.domainExclusionsTip(step: .shown))
    }

    @available(macOS 14.0, *)
    func handleGeoswitchingTipShown() {
        guard !isMenuApp else { return }

        PixelKit.fire(VPNTipPixel.geoswitchingTip(step: .shown))
    }

    @available(macOS 14.0, *)
    func handleStrictRoutingTipShown() {
        guard !isMenuApp else { return }

        PixelKit.fire(VPNTipPixel.strictRoutingTip(step: .shown))
    }
}
