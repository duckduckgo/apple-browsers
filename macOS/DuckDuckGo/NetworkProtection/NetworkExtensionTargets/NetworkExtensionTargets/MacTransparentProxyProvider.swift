//
//  MacTransparentProxyProvider.swift
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
import Common
import FoundationExtensions
import Foundation
import Networking
import NetworkExtension
import NetworkProtectionProxy
import os.log
import PixelKit
import PrivacyConfig
import VPN

final class MacTransparentProxyProvider: TransparentProxyProvider {

    static var vpnProxyLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "DuckDuckGo", category: "VPN Proxy")

    private var cancellables = Set<AnyCancellable>()

    @objc init() {
        let loadSettingsFromStartupOptions: Bool = {
#if NETP_SYSTEM_EXTENSION
            true
#else
            false
#endif
        }()

        /// The defaults the tunnel and proxy share inside this extension's process:
        /// - sysex: tunnel and proxy live in the same binary and share `UserDefaults.standard`
        /// - appex: tunnel writes to `.netP` via the app group; the proxy reads from the same group
        let sharedDefaults: UserDefaults = {
#if NETP_SYSTEM_EXTENSION
            return .standard
#else
            return .netP
#endif
        }()

        let settings = TransparentProxySettings(defaults: sharedDefaults)

        let configuration = TransparentProxyProvider.Configuration(
            loadSettingsFromProviderConfiguration: loadSettingsFromStartupOptions)

        let internalUserDecider = DefaultInternalUserDecider(store: UserDefaults.appConfiguration)
        let channel = StandardApplicationBuildType().channelName(isInternalUser: internalUserDecider.isInternalUser)
#if NETP_SYSTEM_EXTENSION
        let pixelSource = "vpnSystemExtensionProxy"
#else
        let pixelSource = "vpnProxyExtension"
#endif
        let pixelKit = PixelKit(
            dryRun: PixelKitConfig.isDryRun(isProductionBuild: BuildFlags.isProductionBuild),
            appVersion: AppVersion.shared.versionNumber,
            source: pixelSource,
            channel: channel,
            defaultHeaders: [:],
            defaults: sharedDefaults
        ) { (pixelName: String, headers: [String: String], parameters: [String: String], _, _, onComplete: @escaping PixelKit.CompletionBlock) in

            let url = URL.pixelUrl(forPixelNamed: pixelName)
            let apiHeaders = APIRequest.Headers(additionalHeaders: headers)
            let configuration = APIRequest.Configuration(url: url, method: .get, queryParameters: parameters, headers: apiHeaders)
            let request = APIRequest(configuration: configuration)

            request.fetch { _, error in
                onComplete(error == nil, error)
            }
        }

        let eventHandler = TransparentProxyProviderEventHandler(logger: Self.vpnProxyLogger, pixelKit: pixelKit)
        let heartbeatStore = TunnelHeartbeatStore(store: sharedDefaults)

        super.init(settings: settings,
                   configuration: configuration,
                   logger: Self.vpnProxyLogger,
                   eventHandler: eventHandler,
                   heartbeatStore: heartbeatStore)
    }
}
