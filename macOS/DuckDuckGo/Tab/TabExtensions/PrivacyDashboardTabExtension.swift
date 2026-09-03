//
//  PrivacyDashboardTabExtension.swift
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

import BrowserServicesKit
import Combine
import Common
import FoundationExtensions
import ContentBlocking
import Foundation
import MaliciousSiteProtection
import Navigation
import PrivacyConfig
import PrivacyDashboard
import SpecialErrorPages
import WebExtensions
import WebKit

final class PrivacyDashboardTabExtension {

    private let contentBlocking: any ContentBlockingProtocol
    private let certificateTrustEvaluator: CertificateTrustEvaluating
    private let contentScopeExperimentsManager: ContentScopeExperimentsManaging
    private let tabIdentifier: String
    private let webExtensionManagerProvider: @MainActor () -> WebExtensionManaging?
    private var maliciousSiteProtectionStateProvider: MaliciousSiteProtectionStateProvider

    @Published private(set) var privacyInfo: PrivacyInfo?

    private(set) var isCertificateInvalid: Bool?

    private var previousPrivacyInfosByURL: [String: PrivacyInfo] = [:]

    private var cancellables = Set<AnyCancellable>()

    init(tabIdentifier: String,
         webExtensionManagerProvider: @escaping @MainActor () -> WebExtensionManaging?,
         contentBlocking: some ContentBlockingProtocol,
         certificateTrustEvaluator: CertificateTrustEvaluating,
         contentScopeExperimentsManager: ContentScopeExperimentsManaging,
         autoconsentUserScriptPublisher: some Publisher<UserScriptWithAutoconsent?, Never>,
         contentScopeUserScriptPublisher: some Publisher<UserScriptWithContentScope?, Never>,
         didUpgradeToHttpsPublisher: some Publisher<URL, Never>,
         trackersPublisher: some Publisher<DetectedTracker, Never>,
         webViewPublisher: some Publisher<WKWebView, Never>,
         tabCrashPublisher: some Publisher<Void, Never>,
         maliciousSiteProtectionStateProvider: @escaping  MaliciousSiteProtectionStateProvider) {

        self.tabIdentifier = tabIdentifier
        self.webExtensionManagerProvider = webExtensionManagerProvider
        self.contentBlocking = contentBlocking
        self.certificateTrustEvaluator = certificateTrustEvaluator
        self.contentScopeExperimentsManager = contentScopeExperimentsManager
        self.maliciousSiteProtectionStateProvider = maliciousSiteProtectionStateProvider

        tabCrashPublisher.sink { [weak self] in
            Task { @MainActor [weak self] in
                guard #available(macOS 15.4, *), let self else { return }
                self.webExtensionManagerProvider()?.cpmMessagingHealthMonitor.handle(.webContentProcessTerminated(tabIdentifier: self.tabIdentifier))
            }
        }.store(in: &cancellables)

        autoconsentUserScriptPublisher.sink { [weak self] autoconsentUserScript in
            autoconsentUserScript?.delegate = self
        }.store(in: &cancellables)

        contentScopeUserScriptPublisher.sink { [weak self] contentScopeUserScript in
            contentScopeUserScript?.delegate = self
        }.store(in: &cancellables)

        didUpgradeToHttpsPublisher.sink { [weak self] upgradedUrl in
            self?.setMainFrameConnectionUpgradedTo(upgradedUrl)
        }.store(in: &cancellables)

        trackersPublisher.sink { [weak self] tracker in
            guard let self, let url = URL(string: tracker.request.pageUrl) else { return }

            switch tracker.type {
            case .tracker:
                self.privacyInfo?.trackerInfo.addDetectedTracker(tracker.request, onPageWithURL: url)
            case .thirdPartyRequest:
                self.privacyInfo?.trackerInfo.add(detectedThirdPartyRequest: tracker.request)
            case .trackerWithSurrogate(host: let host):
                self.privacyInfo?.trackerInfo.addInstalledSurrogateHost(host, for: tracker.request, onPageWithURL: url)
            }
        }.store(in: &cancellables)

        webViewPublisher.map {
            $0.publisher(for: \.serverTrust)
        }
        .switchToLatest()
        .sink { [weak self] serverTrust in
            Task { [weak self] in
                await self?.updatePrivacyInfo(with: serverTrust)
            }
        }
        .store(in: &cancellables)

        if #available(macOS 15.4, *) {
            NotificationCenter.default
                .publisher(for: .webExtensionAutoconsentDashboardStateRefresh)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] notification in
                    MainActor.assumeMainThread {
                        self?.handleWebExtensionDashboardStateRefresh(notification)
                    }
                }
                .store(in: &cancellables)
        }
    }

    deinit {
        let tabIdentifier = tabIdentifier
        let webExtensionManagerProvider = webExtensionManagerProvider
        Task { @MainActor in
            guard #available(macOS 15.4, *) else { return }
            webExtensionManagerProvider()?.cpmMessagingHealthMonitor.handle(.tabClosed(tabIdentifier: tabIdentifier))
        }
    }

    @available(macOS 15.4, *)
    @MainActor
    private func handleWebExtensionDashboardStateRefresh(_ notification: Notification) {
        guard let url = notification.userInfo?[AutoconsentNotification.UserInfoKeys.url] as? URL,
              let consentStatus = notification.userInfo?[AutoconsentNotification.UserInfoKeys.consentStatus] as? ConsentStatusInfo else {
            return
        }

        privacyInfo?.updateCookieConsentManagedForWebExtensionDashboardState(url: url, consentStatus: consentStatus)
    }

    @MainActor
    private func updatePrivacyInfo(with trust: SecTrust?) async {
        isCertificateInvalid = certificateTrustEvaluator
            .evaluateCertificateTrust(trust: trust)
            .map { !$0 }
        let serverTrustEvaluation = ServerTrustEvaluation(securityTrust: trust, isCertificateInvalid: isCertificateInvalid)
        self.privacyInfo?.serverTrustEvaluation = serverTrustEvaluation
    }

    @MainActor
    private func updateMaliciousSiteInfo(for url: URL?) {
        guard let url, url.isValid,
              !(url.isDuckURLScheme || url.isDuckDuckGo) else { return }
        self.privacyInfo?.malicousSiteThreatKind = maliciousSiteProtectionStateProvider().bypassedMaliciousSiteThreatKind
    }

    @MainActor
    private func resetDashboardInfo(for url: URL, didGoBackForward: Bool) {
        guard url.isHypertextURL else {
            privacyInfo = nil
            return
        }

        if didGoBackForward, let previousPrivacyInfo = previousPrivacyInfosByURL[url.absoluteString] {
            privacyInfo = previousPrivacyInfo
        } else {
            privacyInfo = makePrivacyInfo(url: url)
        }
    }

    @MainActor
    private func makePrivacyInfo(url: URL) -> PrivacyInfo? {
        guard let host = url.host else { return nil }

        let entity = contentBlocking.trackerDataManager.trackerData.findParentEntityOrFallback(forHost: host)

        privacyInfo = PrivacyInfo(url: url,
                                  parentEntity: entity,
                                  protectionStatus: makeProtectionStatus(for: host),
                                  malicousSiteThreatKind: maliciousSiteProtectionStateProvider().bypassedMaliciousSiteThreatKind,
                                  allActiveContentScopeExperiments: contentScopeExperimentsManager.allActiveContentScopeExperiments)
        privacyInfo?.cookieConsentManaged = CookieConsentInfo.initialCPMDiagnostics

        previousPrivacyInfosByURL[url.absoluteString] = privacyInfo

        return privacyInfo
    }

    private func resetConnectionUpgradedTo(navigationAction: NavigationAction) {
        let isOnUpgradedPage = navigationAction.url == privacyInfo?.connectionUpgradedTo
        if navigationAction.isForMainFrame && !isOnUpgradedPage {
            privacyInfo?.connectionUpgradedTo = nil
        }
    }

    public func setMainFrameConnectionUpgradedTo(_ upgradedUrl: URL?) {
        guard let upgradedUrl else { return }
        privacyInfo?.connectionUpgradedTo = upgradedUrl
    }

    private func makeProtectionStatus(for host: String) -> ProtectionStatus {
        let config = contentBlocking.privacyConfigurationManager.privacyConfig

        let isTempUnprotected = config.isTempUnprotected(domain: host)
        let isAllowlisted = config.isUserUnprotected(domain: host)

        var enabledFeatures: [String] = []

        if !config.isInExceptionList(domain: host, forFeature: .contentBlocking) {
            enabledFeatures.append(PrivacyFeature.contentBlocking.rawValue)
        }

        return ProtectionStatus(unprotectedTemporary: isTempUnprotected,
                                enabledFeatures: enabledFeatures,
                                allowlisted: isAllowlisted,
                                denylisted: false)
    }

}

extension PrivacyDashboardTabExtension: NavigationResponder {

    @MainActor
    func didStart(_ navigation: Navigation) {
        guard #available(macOS 15.4, *) else { return }
        webExtensionManagerProvider()?.cpmMessagingHealthMonitor.handle(
            .navigationStarted(tabIdentifier: tabIdentifier, navigationKind: navigation.cpmMessagingNavigationKind)
        )
    }

    @MainActor
    func decidePolicy(for navigationAction: NavigationAction, preferences: inout NavigationPreferences) async -> NavigationActionPolicy? {
        resetConnectionUpgradedTo(navigationAction: navigationAction)
        updateMaliciousSiteInfo(for: navigationAction.url)
        return .next
    }

    @MainActor
    func didCommit(_ navigation: Navigation) {
        resetDashboardInfo(for: navigation.url, didGoBackForward: navigation.navigationAction.navigationType.isBackForward)
        guard #available(macOS 15.4, *), navigation.url.isHypertextURL else { return }
        webExtensionManagerProvider()?.cpmMessagingHealthMonitor.handle(.navigationCommitted(tabIdentifier: tabIdentifier, url: navigation.url))
    }

    @MainActor
    func navigationDidFinish(_ navigation: Navigation) {
        if privacyInfo?.url != navigation.url {
            resetDashboardInfo(for: navigation.url, didGoBackForward: navigation.navigationAction.navigationType.isBackForward)
        }
        guard navigation.url.isHypertextURL else { return }

        guard #available(macOS 15.4, *), let webExtensionManager = webExtensionManagerProvider() else { return }
        webExtensionManager.cpmMessagingHealthMonitor.handle(.navigationFinished(
            tabIdentifier: tabIdentifier,
            url: navigation.url,
            extensionIsLoaded: webExtensionManager.isAutoconsentExtensionLoaded
        ))
    }

    @MainActor
    func navigation(_ navigation: Navigation, didFailWith error: WKError) {
        guard #available(macOS 15.4, *) else { return }
        webExtensionManagerProvider()?.cpmMessagingHealthMonitor.handle(.navigationFailed(tabIdentifier: tabIdentifier))
    }

}

extension Navigation {
    /// Resolves CPM attribution from the first action in a logical navigation.
    /// The current action may describe a redirect rather than the initiating restoration or history load.
    var cpmMessagingNavigationKind: CPMNavigationKind {
        let initialNavigationType = (redirectHistory.first ?? navigationAction).navigationType
        if initialNavigationType == .sessionRestoration {
            return .sessionRestoration
        }
        return initialNavigationType.isBackForward ? .backForward : .other
    }
}

extension PrivacyDashboardTabExtension: AutoconsentUserScriptDelegate {

    func autoconsentUserScript(consentStatus: CookieConsentInfo) {
        self.privacyInfo?.cookieConsentManaged = consentStatus
    }

}

extension PrivacyDashboardTabExtension: ContentScopeUserScriptDelegate {

    func contentScopeUserScript(_ script: BrowserServicesKit.ContentScopeUserScript, didReceiveDebugFlag debugFlag: String) {
        self.privacyInfo?.addDebugFlag(debugFlag)
    }

}

protocol PrivacyDashboardProtocol: AnyObject, NavigationResponder {
    var privacyInfo: PrivacyInfo? { get }
    var privacyInfoPublisher: AnyPublisher<PrivacyInfo?, Never> { get }
    var isCertificateInvalid: Bool? { get }

    func setMainFrameConnectionUpgradedTo(_ upgradedUrl: URL?)
}
extension PrivacyDashboardTabExtension: PrivacyDashboardProtocol, TabExtension {
    typealias PublicProtocol = PrivacyDashboardProtocol
    func getPublicProtocol() -> PublicProtocol { self }

    var privacyInfoPublisher: AnyPublisher<PrivacyDashboard.PrivacyInfo?, Never> {
        self.$privacyInfo.eraseToAnyPublisher()
    }

}

extension Tab {

    var privacyInfo: PrivacyInfo? {
        self.privacyDashboard?.privacyInfo
    }

    var privacyInfoPublisher: AnyPublisher<PrivacyInfo?, Never> {
        self.privacyDashboard?.privacyInfoPublisher ?? Just(nil).eraseToAnyPublisher()
    }

    func setMainFrameConnectionUpgradedTo(_ upgradedUrl: URL?) {
        self.privacyDashboard?.setMainFrameConnectionUpgradedTo(upgradedUrl)
    }

    var isCertificateInvalid: Bool {
        self.privacyDashboard?.isCertificateInvalid ?? false
    }

}

extension TabExtensions {
    var privacyDashboard: PrivacyDashboardProtocol? {
        resolve(PrivacyDashboardTabExtension.self)
    }
}

// MARK: - ConsentStatusInfo to CookieConsentInfo Conversion

@available(macOS 15.4, *)
extension PrivacyInfo {
    /// Dashboard state follows the page across query and fragment changes.
    func matchesForCPMDashboardState(_ refreshURL: URL) -> Bool {
        url.matchesCPMDashboardStatePage(refreshURL)
    }

    func updateCookieConsentManagedForWebExtensionDashboardState(url refreshURL: URL, consentStatus: ConsentStatusInfo) {
        guard matchesForCPMDashboardState(refreshURL) else {
            return
        }

        cookieConsentManaged = consentStatus.toCookieConsentInfo()
    }

}

@available(macOS 15.4, *)
extension ConsentStatusInfo {
    func toCookieConsentInfo() -> CookieConsentInfo {
        CookieConsentInfo(
            consentManaged: consentManaged,
            cosmetic: cosmetic,
            optoutFailed: optoutFailed,
            selftestFailed: selftestFailed,
            consentReloadLoop: consentReloadLoop,
            consentRule: consentRule,
            consentHeuristicEnabled: consentHeuristicEnabled,
            cpmDashboardState: .applied,
            cpmStage: cpmStage.flatMap(CookieConsentCPMStage.init(rawValue:)),
            cpmErrors: cpmErrors,
            cpmQueueSize: cpmQueueSize,
            cpmConfigVersion: cpmConfigVersion
        )
    }
}
