//
//  TunnelControllerViewModel.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import Foundation
import VPN
import NetworkProtectionProxy
import SwiftUI
import SwiftUIExtensions
import TipKit
import VPNAppState

@MainActor
public final class TunnelControllerViewModel: ObservableObject {
    public struct FormattedDataVolume: Equatable {
        public let dataSent: String
        public let dataReceived: String
    }

    /// The NetP service.
    ///
    private let tunnelController: TunnelController

    /// Whether the VPN is enabled
    /// This is determined based on the connection status, same as the iOS version
    ///
    @MainActor
    @Published
    public var isVPNEnabled: Bool

    public var isVPNStagingEnvironmentSelected: Bool {
        vpnSettings.selectedEnvironment == .staging
    }

    public var exclusionsFeatureEnabled: Bool {
        vpnAppState.isUsingSystemExtension
    }

    /// The type of extension that's being used for NetP
    ///
    @Published
    private(set) var onboardingStatus: OnboardingStatus = .completed

    var shouldFlipToggle: Bool {
        // The toggle is not flipped when we're asking to allow a system extension
        // because that step does not result in the tunnel being started.
        onboardingStatus != .isOnboarding(step: .userNeedsToAllowExtension)
    }

    /// The NetP onboarding status publisher
    ///
    private let onboardingStatusPublisher: OnboardingStatusPublisher

    /// The NetP status reporter
    ///
    private let statusReporter: NetworkProtectionStatusReporter

    private let vpnAppState: VPNAppState
    private let vpnSettings: VPNSettings
    private let proxySettings: TransparentProxySettings
    private let locationFormatter: VPNLocationFormatting

    private static let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowsNonnumericFormatting = false
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter
    }()

    private let timeLapsedFormatter: VPNTimeFormatting
    private let uiActionHandler: VPNUIActionHandling

    // MARK: - Misc

    /// The `RunLoop` for the timer.
    ///
    private let runLoopMode: RunLoop.Mode?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization & Deinitialization

    public init(controller: TunnelController,
                onboardingStatusPublisher: OnboardingStatusPublisher,
                statusReporter: NetworkProtectionStatusReporter,
                runLoopMode: RunLoop.Mode? = nil,
                vpnAppState: VPNAppState,
                vpnSettings: VPNSettings,
                proxySettings: TransparentProxySettings,
                locationFormatter: VPNLocationFormatting,
                timeLapsedFormatter: VPNTimeFormatting = VPNTimeFormatter(),
                uiActionHandler: VPNUIActionHandling) {

        self.tunnelController = controller
        self.onboardingStatusPublisher = onboardingStatusPublisher
        self.statusReporter = statusReporter
        self.runLoopMode = runLoopMode
        self.vpnAppState = vpnAppState
        self.vpnSettings = vpnSettings
        self.proxySettings = proxySettings
        self.locationFormatter = locationFormatter
        self.timeLapsedFormatter = timeLapsedFormatter
        self.uiActionHandler = uiActionHandler

        // Get initial connection status
        let initialStatus = statusReporter.statusObserver.recentValue
        connectionStatus = initialStatus

        // Initialize timeLapsed based on initial connection status instead of hardcoding to 0
        switch initialStatus {
        case .connected(let connectedDate):
            let secondsLapsed = Date().timeIntervalSince(connectedDate)
            self.timeLapsed = timeLapsedFormatter.string(from: secondsLapsed)
        default:
            self.timeLapsed = timeLapsedFormatter.string(from: 0)
        }

        dnsSettings = vpnSettings.dnsSettings

        formattedDataVolume = statusReporter.dataVolumeObserver.recentValue.formatted(using: Self.byteCountFormatter)
        internalServerAddress = statusReporter.serverInfoObserver.recentValue.serverAddress
        internalServerAttributes = statusReporter.serverInfoObserver.recentValue.serverLocation
        isVPNEnabled = statusReporter.vpnEnabledObserver.isVPNEnabled

        internalServerLocation = internalServerAttributes?.serverLocation

        subscribeToOnboardingStatusChanges()
        subscribeToStatusChanges()
        subscribeToServerInfoChanges()
        subscribeToDataVolumeUpdates()
        subscribeToVPNEnabledChanges()
        subscribeToToggleDisableChanges()

        vpnSettings.dnsSettingsPublisher
            .assign(to: \.dnsSettings, onWeaklyHeld: self)
            .store(in: &cancellables)
    }

    deinit {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Subscriptions

    private func subscribeToOnboardingStatusChanges() {
        onboardingStatusPublisher
            .receive(on: DispatchQueue.main)
            .assign(to: \.onboardingStatus, onWeaklyHeld: self)
            .store(in: &cancellables)
    }

    private func subscribeToStatusChanges() {
        statusReporter.statusObserver.publisher
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .assign(to: \.connectionStatus, onWeaklyHeld: self)
            .store(in: &cancellables)
    }

    private func subscribeToServerInfoChanges() {
        statusReporter.serverInfoObserver.publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] serverInfo in

            guard let self else {
                return
            }

            Task { @MainActor in
                self.internalServerAddress = serverInfo.serverAddress
                self.internalServerAttributes = serverInfo.serverLocation
                self.internalServerLocation = self.internalServerAttributes?.serverLocation
            }
        }
            .store(in: &cancellables)
    }

    private func subscribeToDataVolumeUpdates() {
        statusReporter.dataVolumeObserver.publisher
            .map { $0.formatted(using: Self.byteCountFormatter) }
            .receive(on: DispatchQueue.main)
            .assign(to: \.formattedDataVolume, onWeaklyHeld: self)
            .store(in: &cancellables)
    }

    private func subscribeToVPNEnabledChanges() {
        statusReporter.vpnEnabledObserver.publisher
            .removeDuplicates()
            .assign(to: \.isVPNEnabled, onWeaklyHeld: self)
            .store(in: &cancellables)
    }

    /// Subscribes to toggle disable changes, and re-enables the toggle after 2 seconds.
    ///
    private func subscribeToToggleDisableChanges() {
        $isToggleDisabled
            .filter { $0 }
            .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self,
                      isToggleDisabled else {
                    return
                }

                isToggleDisabled = false
            }
            .store(in: &cancellables)
    }

    // MARK: - ON/OFF Toggle

    private func startTimer() {
        guard timer == nil else {
            return
        }

        refreshTimeLapsed()

        let newTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in

            guard let self else {
                return
            }

            Task { @MainActor in
                self.refreshTimeLapsed()
            }
        }

        timer = newTimer

        if let runLoopMode = runLoopMode {
            RunLoop.current.add(newTimer, forMode: runLoopMode)
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    @MainActor
    private func updateRefreshTimer() {
        switch connectionStatus {
        case .connected:
            startTimer()
        default:
            stopTimer()
        }
    }

    /// Convenience binding to be able to both query and toggle NetP.
    ///
    @MainActor
    var isToggleOn: Binding<Bool> {
        .init {
            switch self.toggleTransition {
            case .idle:
                break
            case .switchingOn:
                return true
            case .switchingOff:
                return false
            }

            return self.isVPNEnabled
        } set: { [weak self] newValue in
            guard let self else { return }

            guard newValue != self.isVPNEnabled else {
                return
            }

            Task {
                // When turning OFF the VPN we let the parent app offer an alternative
                // UI/UX to prevent it.  If they return `false` in `willStopVPN` the VPN
                // will not be stopped.
                if !newValue, await !self.uiActionHandler.willStopVPN() {
                    return
                }

                if newValue {
                    self.startNetworkProtection()
                } else {
                    self.stopNetworkProtection()
                }
            }
        }
    }

    var isConnectedOrConnecting: Bool {
        switch toggleTransition {
        case .idle:
            break
        case .switchingOn:
            return true
        case .switchingOff:
            return false
        }

        switch connectionStatus {
        case .connecting, .connected, .reasserting:
            return true
        default:
            return false
        }
    }

    // MARK: - Status & health

    private weak var timer: Timer?

    private var previousConnectionStatus: VPN.ConnectionStatus = .default

    @MainActor
    @Published
    private var connectionStatus: VPN.ConnectionStatus {
        didSet {
            previousConnectionStatus = oldValue
            updateRefreshTimer()
            refreshTimeLapsed()
        }
    }

    // MARK: - Connection Status: Toggle State

    enum ToggleTransition: Equatable {
        case idle
        case switchingOn(locallyInitiated: Bool)
        case switchingOff(locallyInitiated: Bool)
    }

    /// Specifies a transition the toggle is undergoing, which will make sure the toggle stays in a position (either ON or OFF)
    /// and ignores intermediate status updates until the transition completes and this is set back to .idle.
    @Published
    private(set) var toggleTransition = ToggleTransition.idle

    @Published
    private(set) var isToggleDisabled: Bool = false

    // MARK: - Connection Status: Timer

    /// The description for the current connection status.
    /// When the status is `connected` this description will also show the time lapsed since connection.
    ///
    @MainActor
    @Published var timeLapsed: String

    @MainActor
    private func refreshTimeLapsed() {
        switch connectionStatus {
        case .connected(let connectedDate):
            timeLapsed = timeLapsedString(since: connectedDate)
        case .disconnecting:
            timeLapsed = timeLapsedFormatter.string(from: 0)
        default:
            timeLapsed = timeLapsedFormatter.string(from: 0)
        }
    }

    /// The description for the current connection status.
    /// When the status is `connected` this description will also show the time lapsed since connection.
    ///
    var connectionStatusDescription: String {
        // If the user is toggling NetP ON or OFF we'll respect the toggle state
        // until it's idle again
        switch toggleTransition {
        case .idle:
            break
        case .switchingOn:
            return UserText.networkProtectionStatusConnecting
        case .switchingOff:
            return UserText.networkProtectionStatusDisconnecting
        }

        switch connectionStatus {
        case .connected:
            return "\(UserText.networkProtectionStatusConnected) · \(timeLapsed)"
        case .connecting, .reasserting:
            return UserText.networkProtectionStatusConnecting
        case .disconnected, .notConfigured:
            return UserText.networkProtectionStatusDisconnected
        case .disconnecting:
            return UserText.networkProtectionStatusDisconnecting
        case .snoozing:
            // Snooze mode is not supported on macOS, but fall back to the disconnected string to be safe.
            return UserText.networkProtectionStatusDisconnected
        }
    }

    private func timeLapsedString(since date: Date) -> String {
        let secondsLapsed = Date().timeIntervalSince(date)
        return timeLapsedFormatter.string(from: secondsLapsed)
    }

    /// The feature status (ON/OFF) right below the main icon.
    ///
    var featureStatusDescription: String {
        switch connectionStatus {
        case .connected, .disconnecting:
            return UserText.networkProtectionStatusViewFeatureOn
        default:
            return UserText.networkProtectionStatusViewFeatureOff
        }
    }

    // MARK: - Server Information

    var showServerDetails: Bool {
        switch connectionStatus {
        case .connected:
            return true
        case .disconnecting:
            if case .connected = previousConnectionStatus {
                return true
            } else {
                return false
            }
        default:
            return false
        }
    }

    @Published
    private var internalServerAddress: String?

    var serverAddress: String {
        guard let internalServerAddress = internalServerAddress else {
            return UserText.networkProtectionServerAddressUnknown
        }

        switch connectionStatus {
        case .connected:
            return internalServerAddress
        case .disconnecting:
            if case .connected = previousConnectionStatus {
                return internalServerAddress
            } else {
                return UserText.networkProtectionServerAddressUnknown
            }
        default:
            return UserText.networkProtectionServerAddressUnknown
        }
    }

    @Published
    var internalServerLocation: String?

    var serverLocation: String {
        guard let internalServerLocation = internalServerLocation else {
            return UserText.networkProtectionServerLocationUnknown
        }

        switch connectionStatus {
        case .connected:
            return UserText.networkProtectionFormattedServerLocation(internalServerLocation)
        case .disconnecting:
            if case .connected = previousConnectionStatus {
                return UserText.networkProtectionFormattedServerLocation(internalServerLocation)
            } else {
                return UserText.networkProtectionServerLocationUnknown
            }
        default:
            return UserText.networkProtectionServerLocationUnknown
        }
    }

    @Published
    private var internalServerAttributes: NetworkProtectionServerInfo.ServerAttributes?

    @Published
    var dnsSettings: NetworkProtectionDNSSettings

    @Published
    var formattedDataVolume: FormattedDataVolume

    var wantsNearestLocation: Bool {
        guard case .nearest = vpnSettings.selectedLocation else { return false }
        return true
    }

    var emoji: String? {
        locationFormatter.emoji(for: internalServerAttributes?.country,
                                preferredLocation: vpnSettings.selectedLocation)
    }

    var plainLocation: String {
        locationFormatter.string(from: internalServerLocation,
                                 preferredLocation: vpnSettings.selectedLocation)
    }

    @available(macOS 12, *)
    func formattedLocation(colorScheme: ColorScheme) -> AttributedString {
        let opacity = colorScheme == .light ? Double(0.6) : Double(0.5)
        return locationFormatter.string(from: internalServerLocation,
                                        preferredLocation: vpnSettings.selectedLocation,
                                        locationTextColor: Color(.defaultText),
                                        preferredLocationTextColor: Color(.defaultText).opacity(opacity))
    }

    // MARK: - Toggling VPN

    private var vpnControlTask: Task<Void, Never>?

    /// Start the VPN.
    ///
    func startNetworkProtection() {
        vpnControlTask?.cancel()

        vpnControlTask = Task { @MainActor in
            if shouldFlipToggle {
                isToggleDisabled = true
                toggleTransition = .switchingOn(locallyInitiated: true)
                updateRefreshTimer()
            }
            defer { toggleTransition = .idle }

            await tunnelController.start()
        }
    }

    /// Stop the VPN.
    ///
    func stopNetworkProtection() {
        vpnControlTask?.cancel()

        vpnControlTask = Task { @MainActor in
            toggleTransition = .switchingOff(locallyInitiated: true)
            updateRefreshTimer()
            defer { toggleTransition = .idle }

            await tunnelController.stop()
        }
    }

    func showLocationSettings() {
        Task { @MainActor in
            await uiActionHandler.showVPNLocations()
        }
    }

#if !APPSTORE && !DEBUG
    func moveToApplications() {
        Task { @MainActor in
            await uiActionHandler.moveAppToApplications()
        }
    }
#endif
}

extension DataVolume {
    func formatted(using formatter: ByteCountFormatter) -> TunnelControllerViewModel.FormattedDataVolume {
        .init(dataSent: formatter.string(fromByteCount: bytesSent),
              dataReceived: formatter.string(fromByteCount: bytesReceived))
    }
}
