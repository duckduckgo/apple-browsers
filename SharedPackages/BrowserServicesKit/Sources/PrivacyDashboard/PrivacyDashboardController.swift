//
//  PrivacyDashboardController.swift
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
import Foundation
import MaliciousSiteProtection
import PrivacyDashboardResources
import WebKit

public enum PrivacyDashboardOpenSettingsTarget: String {

    case general
    case cookiePopupManagement = "cpm"

}

public protocol PrivacyDashboardControllerDelegate: AnyObject {

    func privacyDashboardController(_ privacyDashboardController: PrivacyDashboardController,
                                    didChangeProtectionSwitch protectionState: ProtectionState,
                                    didSendReport: Bool)
    func privacyDashboardController(_ privacyDashboardController: PrivacyDashboardController,
                                    didRequestOpenUrlInNewTab url: URL)
    func privacyDashboardController(_ privacyDashboardController: PrivacyDashboardController,
                                    didRequestOpenSettings target: PrivacyDashboardOpenSettingsTarget)
    func privacyDashboardController(_ privacyDashboardController: PrivacyDashboardController,
                                    didRequestSubmitBrokenSiteReportWithCategory category: String,
                                    description: String)
    func privacyDashboardControllerDidRequestShowGeneralFeedback(_ privacyDashboardController: PrivacyDashboardController)
    func privacyDashboardController(_ privacyDashboardController: PrivacyDashboardController,
                                    didRequestSubmitToggleReportWithSource source: BrokenSiteReport.Source)
    func privacyDashboardControllerDidRequestClose(_ privacyDashboardController: PrivacyDashboardController)
    func privacyDashboardController(_ privacyDashboardController: PrivacyDashboardController, didSetHeight height: Int)

    func privacyDashboardController(_ privacyDashboardController: PrivacyDashboardController,
                                    didSetPermission permissionName: String,
                                    to state: PermissionAuthorizationState)
    func privacyDashboardController(_ privacyDashboardController: PrivacyDashboardController,
                                    setPermission permissionName: String,
                                    paused: Bool)

}

@MainActor public final class PrivacyDashboardController: NSObject {

    public weak var delegate: PrivacyDashboardControllerDelegate?

    @Published public var theme: PrivacyDashboardTheme?
    @Published public var allowedPermissions: [AllowedPermission] = []
    public var preferredLocale: String?
    public var dashboardHtmlName: String {
        #if os(iOS)
        return "ios"
        #else
        return "macos"
        #endif
    }
    public lazy var dashboardHtml: String = {
        guard let file = Bundle.privacyDashboardResourcesBundle.path(forResource: dashboardHtmlName, ofType: "html", inDirectory: "html") else {
            assertionFailure("HTML for the PrivacyDashboard was not found")
            return ""
        }
        guard let html = try? String(contentsOfFile: file) else {
            assertionFailure("Should be able to load HTML as a string")
            return ""
        }
        return html
    }()

    public private(set) weak var privacyInfo: PrivacyInfo?
    private let entryPoint: PrivacyDashboardEntryPoint
    private let eventMapping: EventMapping<PrivacyDashboardEvents>

    weak var webView: WKWebView?
    private var cancellables = Set<AnyCancellable>()

    private let script: PrivacyDashboardUserScript
    private var toggleReportingManager: ToggleReportingManaging

    /// Manages the toggle reporting flow if currently active, otherwise nil.
    var toggleReportingFlow: ToggleReportingFlow?

    public init(privacyInfo: PrivacyInfo?,
                entryPoint: PrivacyDashboardEntryPoint,
                toggleReportingManager: ToggleReportingManaging,
                eventMapping: EventMapping<PrivacyDashboardEvents>) {
        self.privacyInfo = privacyInfo
        self.entryPoint = entryPoint
        self.eventMapping = eventMapping
        self.toggleReportingManager = toggleReportingManager
        script = PrivacyDashboardUserScript()
    }

    public func setup(for webView: WKWebView) {
        self.webView = webView
        webView.navigationDelegate = self

        if #available(iOS 16.4, macOS 13.3, *) {
            webView.isInspectable = true
        } else {
            // Fallback on earlier versions
        }

        setupPrivacyDashboardUserScript()
        loadStartScreen()
        startToggleReportingFlowIfNeeded()
    }

    private func startToggleReportingFlowIfNeeded() {
        if case .toggleReport(let completionHandler) = entryPoint {
            toggleReportingFlow = ToggleReportingFlow(entryPoint: .appMenuProtectionsOff(completionHandler: completionHandler),
                                                      toggleReportingManager: toggleReportingManager,
                                                      controller: self)
        }
    }

    private func setupPrivacyDashboardUserScript() {
        guard let webView else { return }
        script.delegate = self
        webView.configuration.userContentController.addUserScript(script.makeWKUserScriptSync())
        script.messageNames.forEach { messageName in
            webView.configuration.userContentController.add(script, name: messageName)
        }
    }

    private func loadStartScreen() {
        let url = PrivacyDashboardURLBuilder(configuration: .startScreen(entryPoint: entryPoint)).build()
        webView?.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent().deletingLastPathComponent())
    }

    public func updatePrivacyInfo(_ privacyInfo: PrivacyInfo?) {
        cancellables.removeAll()
        self.privacyInfo = privacyInfo

        subscribeToDataModelChanges()
        sendProtectionStatus()
    }

    public func cleanup() {
        cancellables.removeAll()
        script.messageNames.forEach { messageName in
            webView?.configuration.userContentController.removeScriptMessageHandler(forName: messageName)
        }
    }

    public func didStartRulesCompilation() {
        guard let webView else { return }
        script.setIsPendingUpdates(true, webView: webView)
    }

    public func didFinishRulesCompilation() {
        guard let webView else { return }
        script.setIsPendingUpdates(false, webView: webView)
    }

    public func handleViewWillDisappear() {
        toggleReportingFlow?.handleViewWillDisappear()
    }

    public var source: BrokenSiteReport.Source {
        var source: BrokenSiteReport.Source
        switch entryPoint {
        case .report: source = .appMenu
        case .dashboard: source = .dashboard
        case .prompt: source = .prompt
        case .toggleReport: source = .onProtectionsOffMenu
        }
        if let toggleReportingSource = toggleReportingFlow?.entryPoint.source {
            source = toggleReportingSource
        }
        return source
    }

    func didChangeProtectionState(to protectionState: ProtectionState, didSendReport: Bool) {
        delegate?.privacyDashboardController(self, didChangeProtectionSwitch: protectionState, didSendReport: didSendReport)
    }

    func didRequestSubmitToggleReport(with source: BrokenSiteReport.Source) {
        delegate?.privacyDashboardController(self, didRequestSubmitToggleReportWithSource: source)
    }

    func didRequestClose() {
        delegate?.privacyDashboardControllerDidRequestClose(self)
    }

}

// MARK: - WKNavigationDelegate

extension PrivacyDashboardController: WKNavigationDelegate {

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        subscribeToDataModelChanges()

        sendProtectionStatus()
        sendParentEntity()
        sendCurrentLocale()
    }

    private func subscribeToDataModelChanges() {
        cancellables.removeAll()

        subscribeToTheme()
        subscribeToTrackerInfo()
        subscribeToConnectionUpgradedTo()
        subscribeToServerTrust()
        subscribeToConsentManaged()
        subscribeToAllowedPermissions()
        subscribeToMaliciousSiteThreatKind()
    }

    private func subscribeToTheme() {
        $theme
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: { [weak self] themeName in
                guard let self, let webView else { return }
                script.setTheme(themeName, webView: webView)
            })
            .store(in: &cancellables)
    }

    private func subscribeToTrackerInfo() {
        privacyInfo?.$trackerInfo
            .receive(on: DispatchQueue.main)
            .throttle(for: 0.25, scheduler: RunLoop.main, latest: true)
            .sink(receiveValue: { [weak self] trackerInfo in
                guard let self, let url = privacyInfo?.url, let webView else { return }
                script.setTrackerInfo(url, trackerInfo: trackerInfo, webView: webView)
            })
            .store(in: &cancellables)
    }

    private func subscribeToConnectionUpgradedTo() {
        privacyInfo?.$connectionUpgradedTo
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: { [weak self] connectionUpgradedTo in
                guard let self, let webView else { return }
                let upgradedHttps = connectionUpgradedTo != nil
                script.setUpgradedHttps(upgradedHttps, webView: webView)
            })
            .store(in: &cancellables)
    }

    private func subscribeToServerTrust() {
        privacyInfo?.$serverTrustEvaluation
            .receive(on: DispatchQueue.global(qos: .userInitiated))
            .map { serverTrustEvaluation in
                if let serverTrustEvaluation, let securityTrust = serverTrustEvaluation.securityTrust {
                    // swiftlint:disable:next force_cast
                    return ServerTrustViewModel(serverTrust: (securityTrust as! SecTrust), isInvalidCert: serverTrustEvaluation.isCertificateInvalid ?? false)
                }
                return ServerTrustViewModel(serverTrust: nil, isInvalidCert: false)
            }
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: { [weak self] serverTrustViewModel in
                guard let self, let serverTrustViewModel, let webView else { return }
                script.setServerTrust(serverTrustViewModel, webView: webView)
            })
            .store(in: &cancellables)
    }

    private func subscribeToMaliciousSiteThreatKind() {
        privacyInfo?.$malicousSiteThreatKind
            .receive(on: DispatchQueue.main )
            .sink(receiveValue: { [weak self] detectedThreatKind in
                guard let self, let webView else { return }
                script.setMaliciousSiteDetectedThreatKind(detectedThreatKind, webView: webView)
            })
            .store(in: &cancellables)
    }

    private func subscribeToConsentManaged() {
        privacyInfo?.$cookieConsentManaged
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: { [weak self] consentManaged in
                guard let self, let webView else { return }
                script.setConsentManaged(consentManaged, webView: webView)
            })
            .store(in: &cancellables)
    }

    private func subscribeToAllowedPermissions() {
        $allowedPermissions
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: { [weak self] allowedPermissions in
                guard let self, let webView else { return }
                script.setPermissions(allowedPermissions: allowedPermissions, webView: webView)
            })
            .store(in: &cancellables)
    }

    private func sendProtectionStatus() {
        guard let webView, let protectionStatus = privacyInfo?.protectionStatus else { return }
        script.setProtectionStatus(protectionStatus, webView: webView)
    }

    private func sendParentEntity() {
        guard let webView else { return }
        script.setParentEntity(privacyInfo?.parentEntity, webView: webView)
    }

    private func sendCurrentLocale() {
        guard let webView else { return }
        let locale = preferredLocale ?? "en"
        script.setLocale(locale, webView: webView)
    }
}

// MARK: - PrivacyDashboardUserScriptDelegate

extension PrivacyDashboardController: PrivacyDashboardUserScriptDelegate {

    func userScript(_ userScript: PrivacyDashboardUserScript, didRequestOpenSettings target: String) {
        let settingsTarget = PrivacyDashboardOpenSettingsTarget(rawValue: target) ?? .general
        delegate?.privacyDashboardController(self, didRequestOpenSettings: settingsTarget)
    }

    func userScript(_ userScript: PrivacyDashboardUserScript, didChangeProtectionState protectionState: ProtectionState) {
        if shouldSegueToToggleReportScreen(with: protectionState) {
            segueToToggleReportScreen(with: protectionState)
        } else {
            delegate?.privacyDashboardController(self, didChangeProtectionSwitch: protectionState, didSendReport: false)
            delegate?.privacyDashboardControllerDidRequestClose(self)
        }
    }

    private func shouldSegueToToggleReportScreen(with protectionState: ProtectionState) -> Bool {
        !protectionState.isProtected && protectionState.eventOrigin.screen == .primaryScreen && toggleReportingManager.shouldShowToggleReport
    }

    private func segueToToggleReportScreen(with protectionState: ProtectionState) {
        let url = PrivacyDashboardURLBuilder(configuration: .segueToScreen(.toggleReport, entryPoint: entryPoint)).build()
        webView?.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent().deletingLastPathComponent())
        startToggleReportingFlow(with: protectionState)
    }

    private func startToggleReportingFlow(with protectionState: ProtectionState) {
        toggleReportingFlow = ToggleReportingFlow(entryPoint: .dashboardProtectionsOff(protectionStateToSubmitOnDismiss: protectionState),
                                                  toggleReportingManager: toggleReportingManager,
                                                  controller: self)
    }

    func userScript(_ userScript: PrivacyDashboardUserScript, didRequestOpenUrlInNewTab url: URL) {
        delegate?.privacyDashboardController(self, didRequestOpenUrlInNewTab: url)
    }

    func userScriptDidRequestClose(_ userScript: PrivacyDashboardUserScript) {
        toggleReportingFlow?.userScriptDidRequestClose()
        delegate?.privacyDashboardControllerDidRequestClose(self)
    }

    func userScriptDidRequestShowReportBrokenSite(_ userScript: PrivacyDashboardUserScript) {
        eventMapping.fire(.showReportBrokenSite)
    }

    func userScriptDidRequestReportBrokenSiteShown(_ userScript: PrivacyDashboardUserScript) {
        eventMapping.fire(.reportBrokenSiteShown, parameters: [
            PrivacyDashboardEvents.Parameters.source: source.rawValue
        ])
    }

    func userScript(_ userScript: PrivacyDashboardUserScript, setHeight height: Int) {
        delegate?.privacyDashboardController(self, didSetHeight: height)
    }

    func userScript(_ userScript: PrivacyDashboardUserScript, didRequestSubmitBrokenSiteReportWithCategory category: String, description: String) {
        eventMapping.fire(.reportBrokenSiteSent, parameters: [
            PrivacyDashboardEvents.Parameters.source: source.rawValue
        ])
        delegate?.privacyDashboardController(self, didRequestSubmitBrokenSiteReportWithCategory: category, description: description)
    }

    func userScript(_ userScript: PrivacyDashboardUserScript, didSetPermission permission: String, to state: PermissionAuthorizationState) {
        delegate?.privacyDashboardController(self, didSetPermission: permission, to: state)
    }

    func userScript(_ userScript: PrivacyDashboardUserScript, setPermission permission: String, paused: Bool) {
        delegate?.privacyDashboardController(self, setPermission: permission, paused: paused)
    }

    func userScriptDidRequestToggleReportOptions(_ userScript: PrivacyDashboardUserScript) {
        guard let webView else { return }
        let site = privacyInfo?.url.trimmingQueryItemsAndFragment().absoluteString ?? ""
        script.setToggleReportOptions(forSite: site, webView: webView)
    }

    func userScript(_ userScript: PrivacyDashboardUserScript, didSelectReportAction shouldSendReport: Bool) {
        toggleReportingFlow?.userScriptDidSelectReportAction(shouldSendReport: shouldSendReport)
    }

    func userScriptDidRequestShowNativeFeedback(_ userScript: PrivacyDashboardUserScript) {
        delegate?.privacyDashboardControllerDidRequestShowGeneralFeedback(self)
    }

}
