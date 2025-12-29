//
//  NetworkProtectionIPCTunnelController.swift
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

import Common
import Foundation
import VPN
import NetworkProtectionIPC
import PixelKit
import UDSHelper
import os.log
import PrivacyConfig
import VPNAppState

/// VPN tunnel controller through IPC.
///
final class NetworkProtectionIPCTunnelController {

    enum RequestError: CustomNSError {
        case notAuthorizedToEnableLoginItem
        case enableLoginItemError(_ error: Error)
        case ipcControlError(_ error: Error)

        var errorCode: Int {
            switch self {
            case .notAuthorizedToEnableLoginItem: return 0
            case .enableLoginItemError: return 1
                // 100+
            case .ipcControlError: return 100
            }
        }

        var errorUserInfo: [String: Any] {
            switch self {
            case .notAuthorizedToEnableLoginItem:
                return [:]
            case .enableLoginItemError(let error),
                    .ipcControlError(let error):
                return [NSUnderlyingErrorKey: error as NSError]
            }
        }

        var caseDescription: String {
            switch self {
            case .notAuthorizedToEnableLoginItem:
                return "notAuthorizedToEnableLoginItem"
            case .enableLoginItemError:
                return "enableLoginItemError"
            case .ipcControlError:
                return "ipcControlError"
            }
        }
    }

    private let featureGatekeeper: VPNFeatureGatekeeper
    private let loginItemsManager: LoginItemsManaging
    private let ipcClient: NetworkProtectionIPCClient
    private let pixelKit: PixelFiring?
    private let errorRecorder: VPNOperationErrorRecorder
    private let knownFailureStore: NetworkProtectionKnownFailureStore
    private let wideEvent: WideEventManaging
    private let featureFlagger: FeatureFlagger

    // MARK: - User Defaults

    @UserDefaultsWrapper(key: .vpnConnectionWideEventBrowserStartTime, defaultValue: nil, defaults: .netP)
    private var vpnConnectionWideEventBrowserStartTime: Date?

    @UserDefaultsWrapper(key: .vpnConnectionWideEventOverallStartTime, defaultValue: nil, defaults: .netP)
    private var vpnConnectionWideEventOverallStartTime: Date?

    // MARK: - Wide Event
    private var connectionWideEventData: VPNConnectionWideEventData?

    init(featureGatekeeper: VPNFeatureGatekeeper = DefaultVPNFeatureGatekeeper(subscriptionManager: Application.appDelegate.subscriptionManager),
         loginItemsManager: LoginItemsManaging = LoginItemsManager(),
         ipcClient: NetworkProtectionIPCClient,
         fileManager: FileManager = .default,
         pixelKit: PixelFiring? = PixelKit.shared,
         errorRecorder: VPNOperationErrorRecorder = VPNOperationErrorRecorder(),
         knownFailureStore: NetworkProtectionKnownFailureStore = NetworkProtectionKnownFailureStore(),
         wideEvent: WideEventManaging = Application.appDelegate.wideEvent,
         featureFlagger: FeatureFlagger = Application.appDelegate.featureFlagger) {

        self.featureGatekeeper = featureGatekeeper
        self.loginItemsManager = loginItemsManager
        self.ipcClient = ipcClient
        self.pixelKit = pixelKit
        self.errorRecorder = errorRecorder
        self.knownFailureStore = knownFailureStore
        self.wideEvent = wideEvent
        self.featureFlagger = featureFlagger
    }

    // MARK: - Login Items Manager

    private func enableLoginItems() async throws {
        try loginItemsManager.throwingEnableLoginItems(LoginItemsManager.vpnLoginItems)
    }
}

// MARK: - TunnelController Conformance

extension NetworkProtectionIPCTunnelController: TunnelController {

    @MainActor
    func start() async {
        errorRecorder.beginRecordingIPCStart()
        pixelKit?.fire(StartAttempt.begin)
        setupAndStartConnectionWideEvent()

        func handleFailure(_ error: Error) {
            knownFailureStore.lastKnownFailure = KnownFailure(error)
            errorRecorder.recordIPCStartFailure(error)
            log(error)
            pixelKit?.fire(StartAttempt.failure(error), frequency: .legacyDailyAndCount)
        }

        do {
            connectionWideEventData?.browserStartDuration = WideEvent.MeasuredInterval.startingNow()
            guard try await featureGatekeeper.canStartVPN() else {
                let noAuthError = RequestError.notAuthorizedToEnableLoginItem
                completeAndCleanupConnectionWideEvent(with: noAuthError, description: noAuthError.caseDescription)
                throw noAuthError
            }

            do {
                try await enableLoginItems()
            } catch {
                let enableLoginError = RequestError.enableLoginItemError(error)
                completeAndCleanupConnectionWideEvent(with: enableLoginError, description: enableLoginError.caseDescription)
                throw enableLoginError
            }

            knownFailureStore.reset()

            passthroughConnectionWideEventData()
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                ipcClient.start { error in
                    if let error {
                        let error = RequestError.ipcControlError(error)
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }

            pixelKit?.fire(StartAttempt.success, frequency: .legacyDailyAndCount)
            discardWideEvent()
        } catch {
            handleFailure(error)

            switch error {
            case let requestError as RequestError:
                completeAndCleanupConnectionWideEvent(with: requestError, description: requestError.caseDescription)
            default:
                completeAndCleanupConnectionWideEvent(with: error)
            }
        }
    }

    @MainActor
    func stop() async {
        pixelKit?.fire(StopAttempt.begin)

        func handleFailure(_ error: Error) {
            log(error)
            pixelKit?.fire(StopAttempt.failure(error), frequency: .legacyDailyAndCount)
        }

        do {
            do {
                try await enableLoginItems()
            } catch {
                throw RequestError.enableLoginItemError(error)
            }

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                ipcClient.stop { [pixelKit] error in
                    if let error {
                        let error = RequestError.ipcControlError(error)
                        continuation.resume(throwing: error)
                    } else {
                        pixelKit?.fire(StopAttempt.success, frequency: .legacyDailyAndCount)
                        continuation.resume()
                    }
                }
            }
        } catch {
            handleFailure(error)
        }
    }

    func command(_ command: VPNCommand) async throws {
        try await ipcClient.command(command)
    }

    /// Queries VPN to know if it's connected.
    ///
    /// - Returns: `true` if the VPN is connected, connecting or reasserting, and `false` otherwise.
    ///
    var isConnected: Bool {
        get {
            if case .connected = ipcClient.ipcStatusObserver.recentValue {
                return true
            }

            return false
        }
    }

    private func log(_ error: Error) {
        switch error {
        case RequestError.notAuthorizedToEnableLoginItem:
            Logger.networkProtection.error("IPC Controller not authorized to enable the login item: \(error.localizedDescription)")
        case RequestError.enableLoginItemError(let error):
            Logger.networkProtection.error("IPC Controller found an error while enabling the login item: \(error.localizedDescription)")
        default:
            Logger.networkProtection.error("IPC Controller found an unknown error: \(error.localizedDescription)")
        }
    }
}

// MARK: - Start Attempts: Pixels

extension NetworkProtectionIPCTunnelController {

    enum StartAttempt: PixelKitEvent {
        case begin
        case success
        case failure(_ error: Error)

        var name: String {
            switch self {
            case .begin:
                return "netp_browser_start_attempt"

            case .success:
                return "netp_browser_start_success"

            case .failure:
                return "netp_browser_start_failure"
            }
        }

        var parameters: [String: String]? {
            return nil
        }

        var standardParameters: [PixelKitStandardParameter]? {
            switch self {
            case .begin,
                    .success,
                    .failure:
                return [.pixelSource]
            }
        }

    }
}

// MARK: - Stop Attempts

extension NetworkProtectionIPCTunnelController {

    enum StopAttempt: PixelKitEvent {
        case begin
        case success
        case failure(_ error: Error)

        var name: String {
            switch self {
            case .begin:
                return "netp_browser_stop_attempt"

            case .success:
                return "netp_browser_stop_success"

            case .failure:
                return "netp_browser_stop_failure"
            }
        }

        var parameters: [String: String]? {
            return nil
        }

        var standardParameters: [PixelKitStandardParameter]? {
            switch self {
            case .begin,
                    .success,
                    .failure:
                return [.pixelSource]
            }
        }

    }
}

// MARK: - Wide Event

private extension NetworkProtectionIPCTunnelController {

    func setupAndStartConnectionWideEvent() {
        let data = VPNConnectionWideEventData(
            // Only the main tunnel controller can know whether a system extension is being used.
            // At this step we don't know the type of extension yet
            extensionType: .unknown,
            startupMethod: .manualByMainApp,
            isSetup: .unknown,
            onboardingStatus: .unknown,
            contextData: WideEventContextData(name: NetworkProtectionFunnelOrigin.appSettings.rawValue)
        )
        self.connectionWideEventData = data
        wideEvent.startFlow(data)
        data.overallDuration = WideEvent.MeasuredInterval.startingNow()
    }

    func passthroughConnectionWideEventData() {
        guard let data = self.connectionWideEventData else { return }
        vpnConnectionWideEventBrowserStartTime = data.browserStartDuration?.start
        vpnConnectionWideEventOverallStartTime = data.overallDuration?.start
    }

    func completeAndCleanupConnectionWideEvent(with error: Error, description: String? = nil) {
        guard let data = self.connectionWideEventData else { return }
        data.browserStartDuration?.complete()
        data.overallDuration?.complete()
        data.browserStartError = .init(error: error, description: description)
        data.errorData = .init(error: error, description: description)
        wideEvent.completeFlow(data, status: .failure, onComplete: { _, _ in })
        self.connectionWideEventData = nil
        vpnConnectionWideEventBrowserStartTime = nil
        vpnConnectionWideEventOverallStartTime = nil
    }

    func discardWideEvent() {
        guard let data = self.connectionWideEventData else { return }
        wideEvent.discardFlow(data)
        self.connectionWideEventData = nil
    }
}
