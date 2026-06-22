//
//  VPNTipsModel.swift
//  DuckDuckGo
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

import Combine
import CombineExtensions
import Common
import FoundationExtensions
import Core
import VPN
import os.log
import TipKit

public final class VPNTipsModel: ObservableObject {

    static let imageSize = CGSize(width: 32, height: 32)

    @Published
    private(set) var connectionStatus: ConnectionStatus {
        didSet {
            if #available(iOS 18.0, *) {
                handleConnectionStatusChanged(oldValue: oldValue, newValue: connectionStatus)
            } else {
                refreshStrictRoutingReminder()
            }
        }
    }

    /// Drives the pre-iOS-18 fallback reminder view (iOS 18+ uses TipKit instead). Also set when
    /// the debug force flag is on, so the fallback can be exercised on any OS version.
    @Published
    private(set) var showStrictRoutingFallbackReminder = false

    /// How long the user must have had Strict routing disabled before the reminder first appears,
    /// and the interval at which it recurs afterwards. Overridable from the VPN debug menu.
    // TODO: REVERT BEFORE MERGING — hardcoded to 30s for testing (was 7 * 24 * 60 * 60)
    static let defaultStrictRoutingReminderInterval: TimeInterval = 30

    private let vpnSettings: VPNSettings
    private let strictRoutingReminderStore: VPNStrictRoutingReminderStore = DefaultVPNStrictRoutingReminderStore()
    private let strictRoutingReminderFeatureEnabled: Bool
    private var cancellables = Set<AnyCancellable>()

    public init(statusObserver: ConnectionStatusObserver,
                vpnSettings: VPNSettings,
                strictRoutingReminderFeatureEnabled: Bool) {

        self.connectionStatus = statusObserver.recentValue
        self.vpnSettings = vpnSettings
        self.strictRoutingReminderFeatureEnabled = strictRoutingReminderFeatureEnabled

        // The strict-routing reminder runs on all OS versions (TipKit on iOS 18+, a custom
        // fallback view below that), so its subscriptions aren't gated.
        subscribeToConnectionStatusChanges(statusObserver)
        subscribeToEnforceRoutesChanges()

        if #available(iOS 18.0, *) {
            handleConnectionStatusChanged(oldValue: connectionStatus, newValue: connectionStatus)
        } else {
            refreshStrictRoutingReminder()
        }
    }

    deinit {
        geoswitchingStatusUpdateTask?.cancel()
        geoswitchingStatusUpdateTask = nil
    }

    // MARK: - Subscriptions

    private func subscribeToConnectionStatusChanges(_ statusObserver: ConnectionStatusObserver) {
        statusObserver.publisher
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .assign(to: \.connectionStatus, onWeaklyHeld: self)
            .store(in: &cancellables)
    }

    // MARK: - Tips

    let geoswitchingTip = VPNGeoswitchingTip()
    let snoozeTip = VPNSnoozeTip()
    let widgetTip = VPNAddWidgetTip()
    let strictRoutingTip = VPNStrictRoutingTip()

    var geoswitchingStatusUpdateTask: Task<Void, Never>?

    // MARK: - Strict Routing Reminder

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

    /// Recomputes whether the reminder is currently due. The tip first appears only once Strict
    /// routing has been disabled for the interval, then recurs at the same interval until the user
    /// turns it back on (which clears the dates) or dismisses the tip (which invalidates it).
    private func refreshStrictRoutingReminder() {
        guard strictRoutingReminderFeatureEnabled else {
            showStrictRoutingFallbackReminder = false
            if #available(iOS 18.0, *) {
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

        guard #available(iOS 18.0, *) else {
            // No TipKit below iOS 18, so the custom fallback view is the only option.
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
        let otherTipAvailable = [geoswitchingTip.status, snoozeTip.status, widgetTip.status].contains {
            if case .available = $0 { return true }
            return false
        }
        guard !otherTipAvailable else {
            showStrictRoutingFallbackReminder = false
            VPNStrictRoutingTip.shouldShow = false
            return
        }

        // Debug override: render the pre-iOS-18 fallback view in place of the TipKit tip under the
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

    @available(iOS 18.0, *)
    func strictRoutingTipActionHandler(_ action: Tip.Action) {
        if action.id == VPNStrictRoutingTip.ActionIdentifiers.enable.rawValue {
            // Re-enabling routes the change through the settings publisher, which restarts the
            // tunnel and clears the reminder dates.
            vpnSettings.enforceRoutes = true

            strictRoutingTip.invalidate(reason: .actionPerformed)
        }
    }

    // MARK: - Strict Routing Fallback (pre-iOS 18)

    /// Re-evaluates the reminder when the status view appears. Used on the pre-iOS-18 path; iOS 18+
    /// goes through `handleStatusViewAppear`, which also drives the TipKit tips.
    func handleStrictRoutingReminderViewAppear() {
        refreshStrictRoutingReminder()
    }

    func handleStrictRoutingFallbackShown() {
        Pixel.fire(pixel: .networkProtectionStrictRoutingTipShown,
                   withAdditionalParameters: [:],
                   includedParameters: [.appVersion])
    }

    func handleStrictRoutingFallbackEnable() {
        // Re-enabling routes the change through the settings publisher, which restarts the tunnel
        // and clears the reminder dates.
        vpnSettings.enforceRoutes = true
        showStrictRoutingFallbackReminder = false

        Pixel.fire(pixel: .networkProtectionStrictRoutingTipActioned,
                   withAdditionalParameters: [:],
                   includedParameters: [.appVersion])
    }

    func handleStrictRoutingFallbackDismiss() {
        // Mute for the current interval; it recurs at the next interval just like the TipKit tip.
        strictRoutingReminderStore.recordReminderShown()
        showStrictRoutingFallbackReminder = false

        Pixel.fire(pixel: .networkProtectionStrictRoutingTipDismissed,
                   withAdditionalParameters: [:],
                   includedParameters: [.appVersion])
    }

    // MARK: - Tip Action handling

    @available(iOS 18.0, *)
    func snoozeTipActionHandler(_ action: Tip.Action) {
        if action.id == VPNSnoozeTip.ActionIdentifiers.learnMore.rawValue {
            vpnSettings.connectOnLogin = true

            snoozeTip.invalidate(reason: .actionPerformed)
        }
    }

    // MARK: - Handle Refreshing

    @available(iOS 18.0, *)
    private func handleConnectionStatusChanged(oldValue: ConnectionStatus, newValue: ConnectionStatus) {
        switch newValue {
        case .connected:
            if case oldValue = .connecting {
                handleTipDistanceConditionsCheckpoint()
            }

            VPNAddWidgetTip.vpnEnabled = true
            VPNGeoswitchingTip.vpnEnabledOnce = true
            VPNSnoozeTip.vpnEnabled = true
        default:
            if case oldValue = .disconnecting {
                handleTipDistanceConditionsCheckpoint()
            }

            VPNAddWidgetTip.vpnEnabled = false
            VPNSnoozeTip.vpnEnabled = false
        }

        // The reminder is gated on the VPN being connected, so re-evaluate it as the status changes.
        refreshStrictRoutingReminder()
    }

    @available(iOS 18.0, *)
    private func handleTipDistanceConditionsCheckpoint() {
        if case .invalidated = geoswitchingTip.status {
            VPNAddWidgetTip.isDistancedFromPreviousTip = true
        }

        if case .invalidated = widgetTip.status {
            VPNSnoozeTip.isDistancedFromPreviousTip = true
        }
    }

    // MARK: - UI Events

    @available(iOS 18.0, *)
    func handleGeoswitchingTipInvalidated(_ reason: Tip.InvalidationReason) {
        switch reason {
        case .actionPerformed:
            Pixel.fire(pixel: .networkProtectionGeoswitchingTipActioned,
                       withAdditionalParameters: [:],
                       includedParameters: [.appVersion])
        default:
            Pixel.fire(pixel: .networkProtectionGeoswitchingTipDismissed,
                       withAdditionalParameters: [:],
                       includedParameters: [.appVersion])
        }
    }

    @available(iOS 18.0, *)
    func handleSnoozeTipInvalidated(_ reason: Tip.InvalidationReason) {
        switch reason {
        case .actionPerformed:
            Pixel.fire(pixel: .networkProtectionSnoozeTipActioned,
                       withAdditionalParameters: [:],
                       includedParameters: [.appVersion])
        default:
            Pixel.fire(pixel: .networkProtectionSnoozeTipDismissed,
                       withAdditionalParameters: [:],
                       includedParameters: [.appVersion])
        }
    }

    @available(iOS 18.0, *)
    func handleWidgetTipInvalidated(_ reason: Tip.InvalidationReason) {
        switch reason {
        case .actionPerformed:
            Pixel.fire(pixel: .networkProtectionWidgetTipActioned,
                       withAdditionalParameters: [:],
                       includedParameters: [.appVersion])
        default:
            Pixel.fire(pixel: .networkProtectionWidgetTipDismissed,
                       withAdditionalParameters: [:],
                       includedParameters: [.appVersion])
        }
    }

    @available(iOS 18.0, *)
    func handleStrictRoutingTipInvalidated(_ reason: Tip.InvalidationReason) {
        switch reason {
        case .actionPerformed:
            Pixel.fire(pixel: .networkProtectionStrictRoutingTipActioned,
                       withAdditionalParameters: [:],
                       includedParameters: [.appVersion])
        default:
            // Dismissing with the close button mutes the reminder for the current interval; it
            // recurs at the next one. The tip otherwise stays visible until the user acts on it.
            strictRoutingReminderStore.recordReminderShown()

            Pixel.fire(pixel: .networkProtectionStrictRoutingTipDismissed,
                       withAdditionalParameters: [:],
                       includedParameters: [.appVersion])
        }
    }

    // MARK: - User Actions

    @available(iOS 18.0, *)
    func handleUserOpenedWidgetLearnMore() {
        widgetTip.invalidate(reason: .actionPerformed)
    }

    @available(iOS 18.0, *)
    func handleUserOpenedLocations() {
        geoswitchingTip.invalidate(reason: .actionPerformed)
    }

    @available(iOS 18.0, *)
    func handleUserSnoozedVPN() {
        snoozeTip.invalidate(reason: .actionPerformed)
    }

    // MARK: - Status View UI Events

    @available(iOS 18.0, *)
    func handleStatusViewAppear() {
        handleTipDistanceConditionsCheckpoint()
        refreshStrictRoutingReminder()
    }

    @available(iOS 18.0, *)
    func handleStatusViewDisappear() {

        if case .available = geoswitchingTip.status {
            Pixel.fire(pixel: .networkProtectionGeoswitchingTipIgnored,
                       withAdditionalParameters: [:],
                       includedParameters: [.appVersion])
        }

        if case .available = snoozeTip.status {
            Pixel.fire(pixel: .networkProtectionSnoozeTipIgnored,
                       withAdditionalParameters: [:],
                       includedParameters: [.appVersion])
        }

        if case .available = widgetTip.status {
            Pixel.fire(pixel: .networkProtectionWidgetTipIgnored,
                       withAdditionalParameters: [:],
                       includedParameters: [.appVersion])
        }

        if case .available = strictRoutingTip.status {
            Pixel.fire(pixel: .networkProtectionStrictRoutingTipIgnored,
                       withAdditionalParameters: [:],
                       includedParameters: [.appVersion])
        }
    }

    @available(iOS 18.0, *)
    func handleStrictRoutingTipShown() {
        Pixel.fire(pixel: .networkProtectionStrictRoutingTipShown,
                   withAdditionalParameters: [:],
                   includedParameters: [.appVersion])
    }

    @available(iOS 18.0, *)
    func handleGeoswitchingTipShown() {
        Pixel.fire(pixel: .networkProtectionGeoswitchingTipShown,
                   withAdditionalParameters: [:],
                   includedParameters: [.appVersion])
    }

    @available(iOS 18.0, *)
    func handleSnoozeTipShown() {
        Pixel.fire(pixel: .networkProtectionSnoozeTipShown,
                   withAdditionalParameters: [:],
                   includedParameters: [.appVersion])
    }

    @available(iOS 18.0, *)
    func handleWidgetTipShown() {
        Pixel.fire(pixel: .networkProtectionWidgetTipShown,
                   withAdditionalParameters: [:],
                   includedParameters: [.appVersion])
    }
}
