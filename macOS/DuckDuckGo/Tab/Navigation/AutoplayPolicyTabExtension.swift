//
//  AutoplayPolicyTabExtension.swift
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

import Combine
import Foundation
import FeatureFlags
import Navigation
import PrivacyConfig
import UserScript
import WebKit

protocol WebTelemetryUserScriptProvider {
    var webTelemetryScript: WebTelemetryUserScript { get }
}
extension UserScripts: WebTelemetryUserScriptProvider {}

final class AutoplayPolicyTabExtension {

    private let autoplayPreferences: AutoplayPreferences
    private let featureFlagger: FeatureFlagger
    private let permissionManager: PermissionManagerProtocol
    private let permissionSeeder: AutoplayPermissionSeeder

    private weak var telemetryUserScript: WebTelemetryUserScript?
    @Published private(set) var videoPlaybackDetected: Bool = false
    private var cancellables = Set<AnyCancellable>()

    init(
        autoplayPreferences: AutoplayPreferences,
        featureFlagger: FeatureFlagger,
        permissionManager: PermissionManagerProtocol,
        privacyConfigurationManager: PrivacyConfigurationManaging,
        permissionSeeder: AutoplayPermissionSeeder? = nil,
        telemetryScriptPublisher: some Publisher<some WebTelemetryUserScriptProvider, Never>
    ) {
        self.autoplayPreferences = autoplayPreferences
        self.featureFlagger = featureFlagger
        self.permissionManager = permissionManager
        self.permissionSeeder = permissionSeeder ?? AutoplayPermissionSeeder(
            autoplayPreferences: autoplayPreferences,
            permissionManager: permissionManager,
            privacyConfigurationManager: privacyConfigurationManager
        )

        telemetryScriptPublisher
            .sink { [weak self] scripts in
                Task { @MainActor in
                    self?.telemetryUserScript = scripts.webTelemetryScript
                    self?.telemetryUserScript?.delegate = self
                }
            }
            .store(in: &cancellables)
    }
}

extension AutoplayPolicyTabExtension: NavigationResponder {

    @MainActor
    func decidePolicy(for navigationAction: NavigationAction, preferences: inout NavigationPreferences) async -> NavigationActionPolicy? {
        if navigationAction.isForMainFrame {
            videoPlaybackDetected = false
        }

        let mustApplyAutoplayPolicy = mustApplyAutoplayPolicy(url: navigationAction.url)
        preferences.mustApplyAutoplayPolicy = mustApplyAutoplayPolicy

        guard mustApplyAutoplayPolicy else {
            return .next
        }

        // By default we'll install an `.allow` policy (once) for a list of special domains (such as YouTube.com)
        initializeSeededDomainIfNeeded(url: navigationAction.url)

        preferences.autoplayPolicy = loadAutoplayPolicy(url: navigationAction.url)

        return .next
    }
}

private extension AutoplayPolicyTabExtension {

    func mustApplyAutoplayPolicy(url: URL) -> Bool {
        featureFlagger.isFeatureOn(.autoplayPolicy) && url.isHttpOrHttps
    }

    func initializeSeededDomainIfNeeded(url: URL) {
        guard let domain = url.host?.lowercased() else {
            return
        }

        permissionSeeder.seedIfNeeded(domain: domain)
    }

    func loadAutoplayPolicy(url: URL) -> _WKWebsiteAutoplayPolicy {
        if let domain = url.host, let policy = loadAutoplayPolicy(forDomain: domain) {
            return policy
        }

        return loadDefaultAutoplayPolicy()
    }

    func loadAutoplayPolicy(forDomain domain: String) -> _WKWebsiteAutoplayPolicy? {
        guard permissionManager.hasPermissionPersisted(forDomain: domain, permissionType: .autoplayPolicy) else {
            return nil
        }

        let decision = permissionManager.permission(forDomain: domain, permissionType: .autoplayPolicy)
        switch decision {
        case .allow:
            return .allow
        case .ask:
            /// # Note: Autoplay Policy has 3x states. We explicitly remap `ask` > `allowWithSound`
            return .allowWithoutSound
        case .deny:
            return .deny
        }
    }

    func loadDefaultAutoplayPolicy() -> _WKWebsiteAutoplayPolicy {
        .init(autoplayPreferences.autoplayBlockingMode.mediaTypesRequiringUserAction)
    }
}

extension AutoplayPolicyTabExtension: WebTelemetryUserScriptDelegate {
    @MainActor
    func webTelemetryUserScript(_ webTelemetryUserScript: WebTelemetryUserScript,
                                didDetectVideoPlayback payload: WebTelemetryUserScript.VideoPlaybackPayload,
                                in webView: WKWebView?) {

        guard featureFlagger.isFeatureOn(.autoplayPolicy) else {
            return
        }

        videoPlaybackDetected = true
    }
}

protocol AutoplayPolicyTabExtensionProtocol: AnyObject, NavigationResponder {
    var videoPlaybackDetectedPublisher: AnyPublisher<Bool, Never> { get }
}

extension AutoplayPolicyTabExtension: TabExtension, AutoplayPolicyTabExtensionProtocol {
    typealias PublicProtocol = AutoplayPolicyTabExtensionProtocol

    var videoPlaybackDetectedPublisher: AnyPublisher<Bool, Never> {
        $videoPlaybackDetected.eraseToAnyPublisher()
    }

    func getPublicProtocol() -> PublicProtocol { self }
}

extension TabExtensions {
    var autoplayPolicy: AutoplayPolicyTabExtensionProtocol? {
        resolve(AutoplayPolicyTabExtension.self)
    }
}
