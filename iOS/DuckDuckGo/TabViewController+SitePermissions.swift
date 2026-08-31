//
//  TabViewController+SitePermissions.swift
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

import AIChat
import AVFoundation
import BrowserServicesKit
import Combine
import Common
import Core
import FeatureFlags_iOS
import Foundation
import MetricBuilder
import PrivacyConfig
import SitePermissions
import SwiftUI
import WebKit

private final class SitePermissionsManagementPresentationDelegate: NSObject, UIAdaptivePresentationControllerDelegate {

    private let onDismiss: () -> Void

    init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        onDismiss()
    }
}

// Keeps teardown independent of the controller's lifetime while confining permission state to this file.
@MainActor
final class SitePermissionsState {
    fileprivate var coordinator: SitePermissionsCoordinator?
    fileprivate var mediaCaptureUserScript: MediaCaptureUserScript?
    fileprivate var geolocationProvider: GeolocationProvider?
    fileprivate var geolocationUserScript: GeolocationUserScript?
    fileprivate var retiredGeolocationUserScripts = [GeolocationUserScript]()
    fileprivate var shouldRetireGeolocationOnNavigation = false
    fileprivate var isCommittedGeolocationPolicyBlocked = false
    fileprivate var isProvisionalGeolocationPolicyBlocked = false
    fileprivate var dialogHostingController: UIViewController?
    fileprivate var recoveryHostingController: UIViewController?
    fileprivate var managementHostingController: UIHostingController<SitePermissionsSheetView>?
    fileprivate var managementViewModel: SitePermissionsSheetViewModel?
    fileprivate var managementPresentationDelegate: SitePermissionsManagementPresentationDelegate?
    fileprivate var managementCancellables = Set<AnyCancellable>()
    fileprivate var recoveryMessageView: ActionMessageView?
    fileprivate var recoveryCompletion: (() -> Void)?
    fileprivate var recoveryToken: UInt?
    fileprivate var nextRecoveryToken: UInt = 0
    fileprivate var eventHandler: (SitePermissionsEvent) -> Void = { _ in }
    fileprivate struct PendingBridgeRequest {
        let context: SitePermissionRequestContext
        let frame: WKFrameInfo
        let permissionTypes: Set<SitePermissionType>
        let origin: SitePermissionSecurityOrigin
        let webViewID: ObjectIdentifier
        let continuation: CheckedContinuation<MediaCaptureBridgeDecision, Never>
    }
    fileprivate struct MediaCapturePreapproval {
        let requestID: String
        let permissionTypes: Set<SitePermissionType>
        let origin: SitePermissionSecurityOrigin
        // WebKit enforces Permissions Policy before WKUIDelegate. Public WKFrameInfo has no stable
        // cross-callback identity, so bind the remaining same-origin capability to its frame class;
        // same-origin subframes share the top-level principal.
        let isMainFrame: Bool
        let webViewID: ObjectIdentifier
        let webContentProcessGeneration: UInt
        let navigationGeneration: UInt
        let createdAtUptime: TimeInterval
    }
    fileprivate var pendingBridgeRequests = [String: PendingBridgeRequest]()
    fileprivate var handledBridgeRequestIDs = Set<String>()
    fileprivate var mediaCapturePreapprovals = [MediaCapturePreapproval]()
    /// Bounds attacker-controlled outstanding reply continuations without limiting sequential calls on long-lived pages.
    fileprivate let maximumOutstandingBridgeRequests = 256
    fileprivate let preapprovalLifetime: TimeInterval = 5
    fileprivate var committedMainFrameURL: URL?
    fileprivate var committedMediaPolicyBlocks = Set<SitePermissionType>()
    fileprivate var provisionalMediaPolicyBlocks = Set<SitePermissionType>()
    fileprivate var isMainFrameNavigationProvisional = false
    fileprivate var provisionalNavigation: WKNavigation?
    fileprivate var navigationGeneration: UInt = 0
    fileprivate var webContentProcessGeneration: UInt = 0
    fileprivate var isClosed = false

    fileprivate var promptHandlerOverride: SitePermissionsCoordinator.PromptHandler?
    fileprivate var systemSettingsOpenerOverride: (() -> Void)?
    fileprivate var uptimeProvider: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }

    fileprivate var featureFlagSubscription: AnyCancellable?

    fileprivate func dismissDialog() {
        guard let hostingController = dialogHostingController else { return }
        hostingController.willMove(toParent: nil)
        hostingController.view.removeFromSuperview()
        hostingController.removeFromParent()
        dialogHostingController = nil
    }

    fileprivate func dismissRecovery(recoveryToken: UInt? = nil) {
        let recoveryToken = recoveryToken ?? self.recoveryToken
        guard let recoveryToken, recoveryToken == self.recoveryToken else { return }

        if let messageView = recoveryMessageView {
            recoveryMessageView = nil
            messageView.dismissAndFadeOut()
            return
        }

        if let hostingController = recoveryHostingController {
            hostingController.willMove(toParent: nil)
            hostingController.view.removeFromSuperview()
            hostingController.removeFromParent()
            recoveryHostingController = nil
        }
        finishRecovery(recoveryToken: recoveryToken)
    }

    fileprivate func finishRecovery(recoveryToken: UInt) {
        guard recoveryToken == self.recoveryToken else { return }
        let completion = recoveryCompletion
        recoveryCompletion = nil
        self.recoveryToken = nil
        completion?()
    }

    fileprivate func handleManagementDismissal(_ dismissal: SitePermissionsSheetDismissal) {
        if dismissal == .dirty {
            eventHandler(.permissionCenterDismissedDirty)
        }

        managementCancellables.removeAll()
        guard let hostingController = managementHostingController else {
            clearManagementPresentation()
            return
        }
        if hostingController.presentingViewController != nil {
            hostingController.dismiss(animated: true) { [weak self, weak hostingController] in
                guard let self, let hostingController,
                      self.managementHostingController === hostingController else {
                    return
                }
                self.clearManagementPresentation()
            }
        } else {
            clearManagementPresentation()
        }
    }

    fileprivate func dismissManagement() {
        if let managementViewModel {
            managementViewModel.dismiss()
        } else if let managementHostingController {
            managementHostingController.dismiss(animated: false)
            clearManagementPresentation()
        }
    }

    fileprivate func clearManagementPresentation() {
        managementCancellables.removeAll()
        managementHostingController = nil
        managementViewModel = nil
        managementPresentationDelegate = nil
    }

    fileprivate func retireGeolocation() {
        geolocationProvider?.close()
        geolocationUserScript?.cancelAllWatches()
        geolocationUserScript?.delegate = nil
        retiredGeolocationUserScripts.forEach {
            $0.cancelAllWatches()
            $0.delegate = nil
        }
        retiredGeolocationUserScripts.removeAll()
        geolocationProvider = nil
        geolocationUserScript = nil
        shouldRetireGeolocationOnNavigation = false
    }

    fileprivate func discardRetiredGeolocationUserScripts() {
        retiredGeolocationUserScripts.forEach {
            $0.cancelAllWatches()
            $0.delegate = nil
        }
        retiredGeolocationUserScripts.removeAll()
    }

    fileprivate func resetRequests(for pageChange: SitePermissionPageChange) {
        dismissDialog()
        denyPendingBridgeRequests()
        handledBridgeRequestIDs.removeAll()
        mediaCapturePreapprovals.removeAll()
        dismissManagement()
        geolocationProvider?.cancelPageActivity()
        geolocationUserScript?.cancelAllWatches()
        discardRetiredGeolocationUserScripts()
        if shouldRetireGeolocationOnNavigation {
            retireGeolocation()
        }
        coordinator?.pageDidChange(pageChange)
        dismissRecovery()
    }

    fileprivate func denyPendingBridgeRequests() {
        let continuations = pendingBridgeRequests.values.map(\.continuation)
        pendingBridgeRequests.removeAll()
        continuations.forEach { $0.resume(returning: .deny) }
    }

    fileprivate func bypassPendingBridgeRequests() {
        let pendingRequests = pendingBridgeRequests
        pendingBridgeRequests.removeAll()
        handledBridgeRequestIDs.subtract(pendingRequests.keys)
        pendingRequests.values.forEach { $0.continuation.resume(returning: .bypass) }
    }

    fileprivate func discardPreapprovals() {
        handledBridgeRequestIDs.subtract(mediaCapturePreapprovals.map(\.requestID))
        mediaCapturePreapprovals.removeAll()
    }

    func close() {
        featureFlagSubscription = nil
        isClosed = true
        dismissDialog()
        denyPendingBridgeRequests()
        handledBridgeRequestIDs.removeAll()
        mediaCapturePreapprovals.removeAll()
        dismissManagement()
        retireGeolocation()
        coordinator?.close()
        dismissRecovery()
        coordinator = nil
        mediaCaptureUserScript?.delegate = nil
        mediaCaptureUserScript = nil
    }
}

extension TabViewController {

    var sitePermissionsPromptHandlerOverride: SitePermissionsCoordinator.PromptHandler? {
        get { sitePermissionsState.promptHandlerOverride }
        set { sitePermissionsState.promptHandlerOverride = newValue }
    }

    var sitePermissionsSystemSettingsOpenerOverride: (() -> Void)? {
        get { sitePermissionsState.systemSettingsOpenerOverride }
        set { sitePermissionsState.systemSettingsOpenerOverride = newValue }
    }

    var sitePermissionsUptimeProvider: () -> TimeInterval {
        get { sitePermissionsState.uptimeProvider }
        set { sitePermissionsState.uptimeProvider = newValue }
    }

    func subscribeToSitePermissionsChanges() {
        sitePermissionsState.featureFlagSubscription = featureFlagger.updatesPublisher
            .receive(on: DispatchQueue.main)
            .map { [weak self] in self?.isMediaCapturePermissionHandlingEnabled == true }
            .removeDuplicates()
            .sink { [weak self] isEnabled in
                if !isEnabled {
                    self?.configureSitePermissionsMediaCapture(with: nil)
                }
            }
    }

    static func shouldWaitForContentBlockingAssets(assetsInstalled: Bool,
                                                   contentBlockingEnabled: Bool,
                                                   sitePermissionsEnabled: Bool) -> Bool {
        !assetsInstalled && (contentBlockingEnabled || sitePermissionsEnabled)
    }

    func makeTabContentBlockingAssetsPublisher(
        mediaCaptureUserScript: MediaCaptureUserScript
    ) -> AnyPublisher<ContentBlockingUpdating.NewContent, Never> {
        // Content updates rebuild UserScripts, but geolocation owns frame registrations and watch callbacks.
        let geolocationUserScript = sitePermissionsState.geolocationUserScript
            ?? GeolocationUserScript(installImmediately: true)
        geolocationUserScript.activationHandler = { [weak self] frame in
            self?.shouldActivateSitePermissionsGeolocation(in: frame) ?? false
        }

        return contentBlockingAssetsPublisher
            .map { [weak self] content in
                content
                    .includingSitePermissionsMediaCapture(mediaCaptureUserScript)
                    .includingSitePermissionsGeolocation(
                        geolocationUserScript,
                        enabled: self?.featureFlagger.isFeatureOn(.sitePermissions) == true
                    )
            }
            .eraseToAnyPublisher()
    }

    func makeSitePermissionsMediaCaptureUserScript(replacingWebView: Bool) -> MediaCaptureUserScript {
        if replacingWebView {
            sitePermissionsState.mediaCaptureUserScript?.delegate = nil
            sitePermissionsState.mediaCaptureUserScript = nil
        }

        // Install before navigation, even when content-blocking assets are not ready. Keeping
        // the bridge dormant while disabled lets existing documents participate after activation.
        let userScript = MediaCaptureUserScript()
        sitePermissionsState.mediaCaptureUserScript = userScript
        userScript.delegate = self
        return userScript
    }

    func sitePermissionsDidAttachWebView(replacingWebView: Bool) {
        sitePermissionsState.webContentProcessGeneration &+= 1
        sitePermissionsState.committedMainFrameURL = nil
        sitePermissionsState.committedMediaPolicyBlocks.removeAll()
        sitePermissionsState.provisionalMediaPolicyBlocks.removeAll()
        sitePermissionsState.isCommittedGeolocationPolicyBlocked = false
        sitePermissionsState.isMainFrameNavigationProvisional = false
        sitePermissionsState.provisionalNavigation = nil
        sitePermissionsState.isProvisionalGeolocationPolicyBlocked = false
        if replacingWebView {
            sitePermissionsState.resetRequests(for: .webContentProcessReplacement)
        }
        sitePermissionsState.coordinator?.observeMediaCapture(in: webView)
    }

    func sitePermissionsDidCommit(_ webView: WKWebView, navigation: WKNavigation?) {
        if webView === self.webView, isCurrentSitePermissionsProvisionalNavigation(navigation) {
            sitePermissionsState.committedMainFrameURL = webView.url
            sitePermissionsState.committedMediaPolicyBlocks = sitePermissionsState.provisionalMediaPolicyBlocks
            sitePermissionsState.isCommittedGeolocationPolicyBlocked = sitePermissionsState.isProvisionalGeolocationPolicyBlocked
            sitePermissionsState.isMainFrameNavigationProvisional = false
            sitePermissionsState.provisionalNavigation = nil
            sitePermissionsState.isProvisionalGeolocationPolicyBlocked = false
        }
    }

    func sitePermissionsDidStartProvisionalNavigation(_ webView: WKWebView, navigation: WKNavigation?) {
        if webView === self.webView {
            sitePermissionsState.navigationGeneration &+= 1
            sitePermissionsState.isMainFrameNavigationProvisional = true
            sitePermissionsState.provisionalNavigation = navigation
            sitePermissionsState.provisionalMediaPolicyBlocks.removeAll()
            sitePermissionsState.isProvisionalGeolocationPolicyBlocked = false
            sitePermissionsState.resetRequests(for: .navigation)
        }
    }

    func sitePermissionsDidFailProvisionalNavigation(_ webView: WKWebView, navigation: WKNavigation?) {
        if webView === self.webView, isCurrentSitePermissionsProvisionalNavigation(navigation) {
            sitePermissionsState.isMainFrameNavigationProvisional = false
            sitePermissionsState.provisionalNavigation = nil
            sitePermissionsState.provisionalMediaPolicyBlocks.removeAll()
            sitePermissionsState.isProvisionalGeolocationPolicyBlocked = false
        }
    }

    func sitePermissionsWebContentProcessDidTerminate(_ webView: WKWebView) {
        if webView === self.webView {
            sitePermissionsState.webContentProcessGeneration &+= 1
            sitePermissionsState.committedMainFrameURL = nil
            sitePermissionsState.committedMediaPolicyBlocks.removeAll()
            sitePermissionsState.provisionalMediaPolicyBlocks.removeAll()
            sitePermissionsState.isCommittedGeolocationPolicyBlocked = false
            sitePermissionsState.isMainFrameNavigationProvisional = false
            sitePermissionsState.provisionalNavigation = nil
            sitePermissionsState.isProvisionalGeolocationPolicyBlocked = false
            sitePermissionsState.resetRequests(for: .webContentProcessReplacement)
        }
    }

    func prepareSitePermissionsForDataClearing() {
        sitePermissionsState.navigationGeneration &+= 1
        sitePermissionsState.committedMainFrameURL = nil
        sitePermissionsState.isCommittedGeolocationPolicyBlocked = false
        sitePermissionsState.isMainFrameNavigationProvisional = true
        sitePermissionsState.provisionalNavigation = nil
        sitePermissionsState.isProvisionalGeolocationPolicyBlocked = false
        sitePermissionsState.resetRequests(for: .navigation)
    }

    func closeSitePermissions() {
        sitePermissionsState.close()
    }

    func webView(_ webView: WKWebView,
                 requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo,
                 type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        if origin.host.isDuckAIHost {
            guard type == .microphone || type == .cameraAndMicrophone else {
                decisionHandler(.prompt)
                return
            }

            let status = AVCaptureDevice.authorizationStatus(for: .audio)
            decisionHandler(status == .authorized ? .grant : .deny)
            return
        }

        guard featureFlagger.isFeatureOn(.sitePermissions) else {
            sitePermissionsState.discardPreapprovals()
            decisionHandler(.prompt)
            return
        }

        guard webView === self.webView,
              !isLinkPreview,
              let permissionTypes = sitePermissionTypes(for: type),
              consumeMediaCapturePreapproval(for: permissionTypes,
                                             origin: origin,
                                             frame: frame,
                                             webView: webView) else {
            decisionHandler(.deny)
            return
        }
        decisionHandler(.grant)
    }

    var isSitePermissionsManagementAvailable: Bool {
        guard featureFlagger.isFeatureOn(.sitePermissions),
              let site = currentSitePermissionKey(),
              let dependencies = sitePermissionsDependenciesProvider() else {
            return false
        }

        let storedPermissions = dependencies.store.permissions(for: site)
        if storedPermissions[.camera] != nil || storedPermissions[.microphone] != nil {
            return true
        }

        return sitePermissionsState.coordinator?.managementSnapshot(for: site).showsMenuEntry == true
    }

    func presentSitePermissionsManagement() {
        guard sitePermissionsState.managementHostingController == nil,
              isSitePermissionsManagementAvailable,
              let site = currentSitePermissionKey(),
              let dependencies = sitePermissionsDependenciesProvider(),
              let coordinator = makeSitePermissionsCoordinatorIfNeeded(dependencies: dependencies) else {
            return
        }

        let snapshot = coordinator.managementSnapshot(for: site)
        guard snapshot.showsMenuEntry else { return }

        let viewModel = SitePermissionsSheetViewModel(
            snapshot: snapshot,
            store: dependencies.store,
            onDecisionChanged: { [weak self, weak coordinator] change in
                guard let self else { return }
                if self.tabModel.fireTab {
                    coordinator?.applyFireModeManagementDecision(change.to, for: change.permissionType)
                }
                self.fireSitePermissionsEvent(
                    .permissionCenterChanged(type: change.permissionType, from: change.from, to: change.to)
                )
            },
            onRemovePermissions: { [weak self, weak coordinator] removal in
                guard let self else { return }
                coordinator?.removeManagementSessionState(for: removal.permissionTypes, at: site)
                let restore: () -> Void
                if self.tabModel.fireTab {
                    restore = { [weak coordinator] in
                        coordinator?.restoreFireModeManagementState(for: removal.permissionTypes, at: site)
                    }
                } else {
                    restore = { [store = dependencies.store] in
                        store.restore(removal.snapshot)
                    }
                }
                self.presentSitePermissionsRemovalUndo(domain: site.host, restore: restore)
                self.fireSitePermissionsEvent(.permissionRemoveSite)
            },
            onOpenSystemSettings: { [weak self] permissionTypes in
                guard let self,
                      let pixelPermissionType = SitePermissionsEvent.PermissionType(permissionTypes) else {
                    return
                }
                self.fireSitePermissionsEvent(.permissionSystemSettingsOpened(type: pixelPermissionType))
                self.openSitePermissionsSystemSettings()
            },
            onDismiss: { [weak sitePermissionsState] dismissal in
                sitePermissionsState?.handleManagementDismissal(dismissal)
            },
            revokePermissions: { [weak self] permissionTypes in
                self?.revokeSitePermissionsFromManagement(permissionTypes, for: site)
            }
        )
        let hostingController = UIHostingController(rootView: SitePermissionsSheetView(viewModel: viewModel))
        hostingController.view.backgroundColor = UIColor(designSystemColor: .backgroundSheets)
        hostingController.modalTransitionStyle = .coverVertical
        hostingController.modalPresentationStyle = DevicePlatform.isIpad ? .popover : .pageSheet

        sitePermissionsState.managementViewModel = viewModel
        sitePermissionsState.managementHostingController = hostingController
        configureSitePermissionsManagementPresentation(for: hostingController)

        let presentationDelegate = SitePermissionsManagementPresentationDelegate { [weak viewModel] in
            viewModel?.dismiss()
        }
        sitePermissionsState.managementPresentationDelegate = presentationDelegate
        hostingController.presentationController?.delegate = presentationDelegate
        observeSitePermissionsManagement(coordinator: coordinator, site: site, viewModel: viewModel)

        present(hostingController, animated: true) { [weak self, weak hostingController] in
            guard let self,
                  let hostingController,
                  self.sitePermissionsState.managementHostingController === hostingController,
                  hostingController.presentingViewController != nil else {
                return
            }
            self.fireSitePermissionsEvent(.permissionCenterOpened)
        }
    }

    private func observeSitePermissionsManagement(coordinator: SitePermissionsCoordinator,
                                                  site: SitePermissionKey,
                                                  viewModel: SitePermissionsSheetViewModel) {
        sitePermissionsState.managementCancellables.removeAll()

        coordinator.$captureStates
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak coordinator, weak viewModel] _ in
                guard let self, let coordinator, let viewModel else { return }
                self.refreshSitePermissionsManagement(coordinator: coordinator, site: site, viewModel: viewModel)
            }
            .store(in: &sitePermissionsState.managementCancellables)

        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak coordinator, weak viewModel] _ in
                guard let self, let coordinator, let viewModel else { return }
                self.refreshSitePermissionsManagement(coordinator: coordinator, site: site, viewModel: viewModel)
            }
            .store(in: &sitePermissionsState.managementCancellables)
    }

    private func refreshSitePermissionsManagement(coordinator: SitePermissionsCoordinator,
                                                  site: SitePermissionKey,
                                                  viewModel: SitePermissionsSheetViewModel) {
        guard featureFlagger.isFeatureOn(.sitePermissions), currentSitePermissionKey() == site else {
            viewModel.dismiss()
            return
        }
        viewModel.refresh(with: coordinator.managementSnapshot(for: site))
    }

    private func configureSitePermissionsManagementPresentation(for hostingController: UIHostingController<SitePermissionsSheetView>) {
        let presentingWidth = view.frame.width

        if let popover = hostingController.popoverPresentationController {
            guard let sourceView = chromeDelegate?.omniBar.barView.menuButton ?? view else { return }
            popover.sourceView = sourceView
            popover.sourceRect = sourceView.bounds

            let height = sitePermissionsManagementContentHeight(for: hostingController, width: 375)
            hostingController.preferredContentSize = CGSize(width: 375, height: height)
            if #available(iOS 16.4, *) {
                hostingController.safeAreaRegions = [.container]
            }
            configureSitePermissionsManagementDetents(
                popover.adaptiveSheetPresentationController,
                hostingController: hostingController,
                presentingWidth: presentingWidth
            )
        }

        if let sheet = hostingController.sheetPresentationController {
            configureSitePermissionsManagementDetents(
                sheet,
                hostingController: hostingController,
                presentingWidth: presentingWidth
            )
        }
    }

    private func configureSitePermissionsManagementDetents(_ sheet: UISheetPresentationController,
                                                           hostingController: UIHostingController<SitePermissionsSheetView>,
                                                           presentingWidth: CGFloat) {
        if #available(iOS 16.0, *) {
            let contentHeight = sitePermissionsManagementContentHeight(for: hostingController, width: presentingWidth)
            sheet.detents = [.custom { context in
                min(contentHeight, context.maximumDetentValue * 0.9)
            }]
            sheet.prefersEdgeAttachedInCompactHeight = true
            sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = true
        } else {
            sheet.detents = [.large()]
        }
        sheet.prefersGrabberVisible = true
        if #unavailable(iOS 26) {
            sheet.preferredCornerRadius = SheetMetrics.cornerRadius
        }
    }

    private func sitePermissionsManagementContentHeight(for hostingController: UIHostingController<SitePermissionsSheetView>,
                                                        width: CGFloat) -> CGFloat {
        guard #available(iOS 16.0, *) else { return 520 }
        let sizingController = UIHostingController(rootView: hostingController.rootView)
        sizingController.disableSafeArea()
        return sizingController.sizeThatFits(in: CGSize(width: width, height: .infinity)).height
    }

    private func presentSitePermissionsRemovalUndo(domain: String, restore: @escaping () -> Void) {
        ActionMessageView.present(
            message: String(format: UserText.settingsSitePermissionsRemovedSiteFormat, domain),
            actionTitle: UserText.actionGenericUndo,
            presentationLocation: .withBottomBar(andAddressBarBottom: appSettings.currentAddressBarPosition.isBottom),
            onAction: { [weak self] in
                restore()
                self?.fireSitePermissionsEvent(.permissionRemoveUndo)
            }
        )
    }

    func revokeSitePermissions(_ permissionTypes: Set<SitePermissionType>, for site: SitePermissionKey) {
        let committedSite = sitePermissionsState.committedMainFrameURL.flatMap(SitePermissionKey.init(committedURL:))
        guard committedSite == site else { return }

        webView.revokeSitePermissions(permissionTypes)
        sitePermissionsState.coordinator?.revokeManagementSessionState(for: permissionTypes, at: site)
    }

    func revokeSitePermissionsFromManagement(_ permissionTypes: Set<SitePermissionType>, for site: SitePermissionKey) {
        revokeSitePermissions(permissionTypes, for: site)
        guard !tabModel.fireTab, let dependencies = sitePermissionsDependenciesProvider() else { return }
        dependencies.revokePermissionsInOtherTabs(site, permissionTypes, tabModel.uid)
    }

    private func sitePermissionTypes(for captureType: WKMediaCaptureType) -> Set<SitePermissionType>? {
        switch captureType {
        case .camera:
            return [.camera]
        case .microphone:
            return [.microphone]
        case .cameraAndMicrophone:
            return [.camera, .microphone]
        @unknown default:
            return nil
        }
    }

    private func makeSitePermissionsCoordinatorIfNeeded(dependencies: SitePermissionsDependencies) -> SitePermissionsCoordinator? {
        guard !sitePermissionsState.isClosed else { return nil }
        if let coordinator = sitePermissionsState.coordinator {
            return coordinator
        }

        sitePermissionsState.eventHandler = dependencies.eventHandler
        let coordinator = SitePermissionsCoordinator(
            store: dependencies.store,
            systemPermissionClient: dependencies.systemPermissionClient,
            isFireMode: tabModel.fireTab,
            currentContext: { [weak self] tabID, requestingFrameID in
                self?.currentSitePermissionContext(tabID: tabID, requestingFrameID: requestingFrameID)
            },
            recoveryHandler: { [weak self] recovery, completion in
                guard let self else {
                    completion()
                    return
                }
                presentSitePermissionRecovery(recovery, completion: completion)
            },
            eventHandler: { [weak self] event in
                self?.fireSitePermissionsEvent(event)
            }
        )
        coordinator.observeMediaCapture(in: webView)
        sitePermissionsState.coordinator = coordinator
        return coordinator
    }

    func configureSitePermissionsGeolocation(with userScript: GeolocationUserScript?) {
        guard let userScript else {
            // An already-loaded page keeps its injected shim until the next navigation. Retain its
            // weakly-held message handler until then so outstanding page promises still resolve.
            sitePermissionsState.shouldRetireGeolocationOnNavigation = sitePermissionsState.geolocationUserScript != nil
            return
        }
        userScript.activationHandler = { [weak self] frame in
            self?.shouldActivateSitePermissionsGeolocation(in: frame) ?? false
        }
        if sitePermissionsState.geolocationUserScript === userScript {
            sitePermissionsState.shouldRetireGeolocationOnNavigation = false
            if let provider = sitePermissionsState.geolocationProvider {
                userScript.delegate = provider
                return
            }
        } else {
            if let currentScript = sitePermissionsState.geolocationUserScript {
                sitePermissionsState.retiredGeolocationUserScripts.append(currentScript)
            }
            sitePermissionsState.geolocationUserScript = userScript
            sitePermissionsState.shouldRetireGeolocationOnNavigation = false
        }
        if let provider = sitePermissionsState.geolocationProvider {
            userScript.delegate = provider
            return
        }
        guard featureFlagger.isFeatureOn(.sitePermissions),
              let dependencies = sitePermissionsDependenciesProvider(),
              makeSitePermissionsCoordinatorIfNeeded(dependencies: dependencies) != nil else {
            return
        }

        let provider = GeolocationProvider(
            systemPermissionClient: dependencies.systemPermissionClient,
            contextProvider: { [weak self] frame in
                self?.makeGeolocationSitePermissionContext(for: frame)
            },
            requestPermission: { [weak self] context, completion in
                guard let self, let coordinator = sitePermissionsState.coordinator else {
                    completion(.deny(systemBlocks: []))
                    return
                }
                coordinator.request(
                    SitePermissionRequest(context: context, permissionTypes: [.location]),
                    promptHandler: sitePermissionsPromptHandler(),
                    completion: completion
                )
            },
            queryPermission: { [weak self] context in
                self?.sitePermissionsState.coordinator?.queryState(for: .location, context: context) ?? .denied
            }
        )
        sitePermissionsState.geolocationProvider = provider
        userScript.delegate = provider
    }

    private func shouldActivateSitePermissionsGeolocation(in frame: GeolocationFrame) -> Bool {
        let host = frame.securityOrigin.host.lowercased()
        return featureFlagger.isFeatureOn(.sitePermissions)
            && !sitePermissionsState.isClosed
            && !isLinkPreview
            && !isError
            && frame.isAssociated(with: webView)
            && !host.isEmpty
            && isSecureGeolocationOrigin(frame.securityOrigin)
            && host != "duck.ai"
            && !host.hasSuffix(".duck.ai")
    }

    func makeGeolocationSitePermissionContext(for frame: GeolocationFrame) -> SitePermissionRequestContext? {
        guard featureFlagger.isFeatureOn(.sitePermissions),
              !sitePermissionsState.isClosed,
              frame.isAssociated(with: webView),
              !isLinkPreview,
              !isError,
              !sitePermissionsState.isCommittedGeolocationPolicyBlocked,
              let committedURL = sitePermissionsState.committedMainFrameURL,
              let topLevelSite = currentSitePermissionKey(),
              isSecureGeolocationOrigin(frame.securityOrigin),
              Self.isSameOrigin(frame.securityOrigin, as: committedURL) else {
            return nil
        }

        return SitePermissionRequestContext(
            tabID: tabModel.uid,
            topLevelSite: topLevelSite,
            requestingFrameID: frame.requestingFrameID,
            webContentProcessGeneration: sitePermissionsState.webContentProcessGeneration,
            navigationGeneration: sitePermissionsState.navigationGeneration
        )
    }

    private func isSecureGeolocationOrigin(_ origin: WKSecurityOrigin) -> Bool {
        let scheme = origin.protocol.lowercased()
        guard !origin.host.isEmpty,
              scheme == "https" || scheme == "http" else { return false }
        guard scheme == "http" else { return true }

        let host = origin.host.lowercased()
        let ipv4Octets = host.split(separator: ".", omittingEmptySubsequences: false)
        let isIPv4Loopback = ipv4Octets.count == 4
            && ipv4Octets.allSatisfy { UInt8($0) != nil }
            && UInt8(ipv4Octets[0]) == 127
        return host == "localhost"
            || host.hasSuffix(".localhost")
            || host == "::1"
            || host == "[::1]"
            || isIPv4Loopback
    }

    /// Cross-origin delegation is intentionally unsupported in v1 because the shim cannot reliably
    /// evaluate subframe response headers and `allow="geolocation"`. Revisit only with breakage evidence
    /// or an availability-gated OS-managed API; until then, native attribution denies every cross-origin frame.
    private static func isSameOrigin(_ origin: WKSecurityOrigin, as url: URL) -> Bool {
        let originScheme = origin.protocol.lowercased()
        let urlScheme = url.scheme?.lowercased()
        guard let urlScheme,
              let urlHost = url.host,
              !origin.host.isEmpty,
              originScheme == urlScheme,
              normalizedOriginHost(origin.host) == normalizedOriginHost(urlHost) else { return false }

        let originPort = origin.port == 0 ? defaultPort(for: originScheme) : origin.port
        let urlPort = url.port ?? defaultPort(for: urlScheme)
        return originPort == urlPort
    }

    private static func normalizedOriginHost(_ host: String) -> String {
        host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
    }

    private static func defaultPort(for scheme: String) -> Int? {
        switch scheme {
        case "http":
            return 80
        case "https":
            return 443
        default:
            return nil
        }
    }

    func captureSitePermissionsGeolocationPolicy(from response: URLResponse, isForMainFrame: Bool) {
        guard isForMainFrame,
              sitePermissionsState.isMainFrameNavigationProvisional else { return }

        let header = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Permissions-Policy")
        sitePermissionsState.isProvisionalGeolocationPolicyBlocked = Self.permissionsPolicyDisablesGeolocation(
            header,
            for: response.url
        )
    }

    static func permissionsPolicyDisablesGeolocation(_ header: String?, for pageURL: URL?) -> Bool {
        guard let header else { return false }

        let geolocationAllowLists = header.split(separator: ",", omittingEmptySubsequences: false).compactMap { directive -> Substring? in
            let components = directive.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard components.count == 2,
                  components[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "geolocation" else {
                return nil
            }
            return components[1]
        }

        return geolocationAllowLists.contains { !geolocationAllowList($0, includes: pageURL) }
    }

    private static func geolocationAllowList(_ rawValue: Substring, includes pageURL: URL?) -> Bool {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value == "*" { return true }
        guard value.first == "(", value.last == ")" else { return false }

        let allowList = value.dropFirst().dropLast().split(whereSeparator: { $0.isWhitespace })
        return allowList.contains { rawToken in
            let token = rawToken.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if token.lowercased() == "self" || token == "*" { return true }
            guard let pageURL, let allowedURL = URL(string: token) else { return false }
            return sameOrigin(allowedURL, pageURL)
        }
    }

    private static func sameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        guard let lhsScheme = lhs.scheme?.lowercased(),
              let rhsScheme = rhs.scheme?.lowercased(),
              let lhsHost = lhs.host,
              let rhsHost = rhs.host else { return false }
        return lhsScheme == rhsScheme
            && normalizedOriginHost(lhsHost) == normalizedOriginHost(rhsHost)
            && (lhs.port ?? defaultPort(for: lhsScheme)) == (rhs.port ?? defaultPort(for: rhsScheme))
    }

    private func currentSitePermissionContext(tabID: String, requestingFrameID: UInt64) -> SitePermissionRequestContext? {
        let context: SitePermissionRequestContext
        if let pendingRequest = sitePermissionsState.pendingBridgeRequests.values
            .map({ ($0.context, $0.frame) })
            .first(where: { $0.0.tabID == tabID && $0.0.requestingFrameID == requestingFrameID }) {
            // WKFrameInfo exposes identity but no public liveness API. Holding the exact frame object,
            // together with navigation and process generations, is the strongest public validation;
            // same-document iframe removal cannot be observed here.
            guard pendingRequest.0.requestingFrameID
                    == UInt64(UInt(bitPattern: ObjectIdentifier(pendingRequest.1))) else { return nil }
            context = pendingRequest.0
        } else if let geolocationContext = sitePermissionsState.geolocationProvider?.currentContext(
            tabID: tabID,
            requestingFrameID: requestingFrameID
        ) {
            context = geolocationContext
        } else {
            return nil
        }

        guard tabID == tabModel.uid,
              context.webContentProcessGeneration == sitePermissionsState.webContentProcessGeneration,
              context.navigationGeneration == sitePermissionsState.navigationGeneration,
              context.topLevelSite == currentSitePermissionKey() else {
            return nil
        }
        return context
    }

    private func sitePermissionsPromptHandler() -> SitePermissionsCoordinator.PromptHandler {
        sitePermissionsPromptHandlerOverride ?? { [weak self] prompt, completion in
            guard let self else {
                completion(.denyOnce)
                return
            }
            presentSitePermissionDialog(prompt, completion: completion)
        }
    }

    private func consumeMediaCapturePreapproval(for permissionTypes: Set<SitePermissionType>,
                                                origin: WKSecurityOrigin,
                                                frame: WKFrameInfo,
                                                webView: WKWebView) -> Bool {
        let webViewID = ObjectIdentifier(webView)
        pruneExpiredMediaCapturePreapprovals()
        let staleRequestIDs = sitePermissionsState.mediaCapturePreapprovals.filter {
            $0.webViewID != webViewID
                || $0.webContentProcessGeneration != sitePermissionsState.webContentProcessGeneration
                || $0.navigationGeneration != sitePermissionsState.navigationGeneration
        }.map(\.requestID)
        sitePermissionsState.handledBridgeRequestIDs.subtract(staleRequestIDs)
        sitePermissionsState.mediaCapturePreapprovals.removeAll { staleRequestIDs.contains($0.requestID) }

        let trustedOrigin = SitePermissionSecurityOrigin(frame.securityOrigin)
        guard trustedOrigin == SitePermissionSecurityOrigin(origin),
              let index = sitePermissionsState.mediaCapturePreapprovals.firstIndex(where: {
                  $0.permissionTypes == permissionTypes
                      && $0.origin == trustedOrigin
                      && $0.isMainFrame == frame.isMainFrame
                      && $0.webViewID == webViewID
              }) else {
            return false
        }
        let preapproval = sitePermissionsState.mediaCapturePreapprovals.remove(at: index)
        sitePermissionsState.handledBridgeRequestIDs.remove(preapproval.requestID)
        return true
    }

    private func pruneExpiredMediaCapturePreapprovals() {
        let now = sitePermissionsUptimeProvider()
        let expiredRequestIDs = sitePermissionsState.mediaCapturePreapprovals.filter {
            now - $0.createdAtUptime >= sitePermissionsState.preapprovalLifetime
        }.map(\.requestID)
        sitePermissionsState.handledBridgeRequestIDs.subtract(expiredRequestIDs)
        sitePermissionsState.mediaCapturePreapprovals.removeAll { expiredRequestIDs.contains($0.requestID) }
    }

    private func currentSitePermissionKey() -> SitePermissionKey? {
        guard !sitePermissionsState.isMainFrameNavigationProvisional else { return nil }
        return sitePermissionsState.committedMainFrameURL.flatMap(SitePermissionKey.init(committedURL:))
    }

    private func isCurrentSitePermissionsProvisionalNavigation(_ navigation: WKNavigation?) -> Bool {
        guard sitePermissionsState.isMainFrameNavigationProvisional else { return true }
        switch (sitePermissionsState.provisionalNavigation, navigation) {
        case let (current?, callback?):
            return current === callback
        case (nil, nil):
            return true
        default:
            return false
        }
    }

    private func presentSitePermissionDialog(_ prompt: SitePermissionPrompt,
                                             completion: @escaping (SitePermissionPromptDecision) -> Void) {
        guard let viewModel = SitePermissionDialogViewModel(
                  prompt: prompt,
                  isDuckDuckGoSERP: prompt.permissionTypes == [.location]
                      && sitePermissionsState.committedMainFrameURL?.isDuckDuckGoSearch == true
              ),
              let pixelPermissionType = SitePermissionsEvent.PermissionType(prompt.permissionTypes) else {
            completion(.denyOnce)
            return
        }

        sitePermissionsState.dismissDialog()
        let dialog = SitePermissionDialogView(viewModel: viewModel) { [weak self] action in
            guard let self else { return }
            fireSitePermissionsEvent(.permissionDialogClick(type: pixelPermissionType,
                                                             selection: action.pixelDialogSelection))
            sitePermissionsState.dismissDialog()
            completion(action.promptDecision)
        }
        let hostingController = UIHostingController(rootView: dialog)
        hostingController.view.backgroundColor = .clear
        hostingController.view.accessibilityViewIsModal = true
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        addChild(hostingController)
        view.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        hostingController.didMove(toParent: self)
        sitePermissionsState.dialogHostingController = hostingController
        fireSitePermissionsEvent(.permissionDialogImpression(type: pixelPermissionType))
    }

    private func presentSitePermissionRecovery(_ recovery: SitePermissionRecovery,
                                               completion: @escaping () -> Void) {
        sitePermissionsState.nextRecoveryToken &+= 1
        let recoveryToken = sitePermissionsState.nextRecoveryToken
        sitePermissionsState.recoveryToken = recoveryToken
        sitePermissionsState.recoveryCompletion = completion

        switch recovery {
        case .toast(let permissionTypes):
            guard let message = PermissionReminderDialogViewModel.sitePermissionToastMessage(for: permissionTypes) else {
                sitePermissionsState.finishRecovery(recoveryToken: recoveryToken)
                return
            }

            let messageView = ActionMessageView.presentTracked(
                message: message,
                presentationLocation: .withBottomBar(andAddressBarBottom: appSettings.currentAddressBarPosition.isBottom),
                onDidDismiss: { [weak self] in
                    guard self?.sitePermissionsState.recoveryToken == recoveryToken else { return }
                    self?.sitePermissionsState.recoveryMessageView = nil
                    self?.sitePermissionsState.finishRecovery(recoveryToken: recoveryToken)
                }
            )
            guard let messageView else {
                sitePermissionsState.finishRecovery(recoveryToken: recoveryToken)
                return
            }
            sitePermissionsState.recoveryMessageView = messageView

        case .reminder(let permissionTypes):
            guard let viewModel = PermissionReminderDialogViewModel(sitePermissionTypes: permissionTypes),
                  let pixelPermissionType = SitePermissionsEvent.PermissionType(permissionTypes) else {
                sitePermissionsState.finishRecovery(recoveryToken: recoveryToken)
                return
            }

            let dialog = PermissionReminderDialogView(viewModel: viewModel) { [weak self] action in
                guard let self else { return }
                switch action {
                case .changePermissions:
                    fireSitePermissionsEvent(.permissionReminderDialog(type: pixelPermissionType, action: .settings))
                    fireSitePermissionsEvent(.permissionSystemSettingsOpened(type: pixelPermissionType))
                    sitePermissionsState.dismissRecovery(recoveryToken: recoveryToken)
                    openSitePermissionsSystemSettings()
                case .cancel:
                    fireSitePermissionsEvent(.permissionReminderDialog(type: pixelPermissionType, action: .cancel))
                    sitePermissionsState.dismissRecovery(recoveryToken: recoveryToken)
                case .hideVoiceSearch:
                    assertionFailure("Hide Voice Search is not available in a site permission reminder")
                    sitePermissionsState.dismissRecovery(recoveryToken: recoveryToken)
                }
            }
            let hostingController = UIHostingController(rootView: dialog)
            hostingController.view.backgroundColor = .clear
            hostingController.view.accessibilityViewIsModal = true
            hostingController.view.translatesAutoresizingMaskIntoConstraints = false

            addChild(hostingController)
            view.addSubview(hostingController.view)
            NSLayoutConstraint.activate([
                hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
                hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
            hostingController.didMove(toParent: self)
            sitePermissionsState.recoveryHostingController = hostingController
            fireSitePermissionsEvent(.permissionReminderDialog(type: pixelPermissionType, action: .shown))
        }
    }

    private func fireSitePermissionsEvent(_ event: SitePermissionsEvent) {
        // Phase 6 owns geolocation instrumentation. Keep the Phase 5 flow silent while reusing the
        // coordinator paths that already emit camera and microphone events.
        switch event {
        case .permissionDialogImpression(type: .geolocation),
             .permissionDialogClick(type: .geolocation, selection: _),
             .permissionSystemPromptResult(type: .location, result: _),
             .permissionReminderDialog(type: .geolocation, action: _),
             .permissionSystemSettingsOpened(type: .geolocation):
            return
        default:
            break
        }
        sitePermissionsState.eventHandler(event)
    }

    private func openSitePermissionsSystemSettings() {
        if let sitePermissionsSystemSettingsOpenerOverride {
            sitePermissionsSystemSettingsOpenerOverride()
            return
        }
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - MediaCaptureUserScriptDelegate

extension TabViewController: MediaCaptureUserScriptDelegate {

    var isMediaCapturePermissionHandlingEnabled: Bool {
        featureFlagger.isFeatureOn(.sitePermissions)
    }

    func configureSitePermissionsMediaCapture(with userScript: MediaCaptureUserScript?) {
        guard let userScript else {
            // Keep the reply handler alive for existing and back-forward-cached documents.
            sitePermissionsState.dismissDialog()
            sitePermissionsState.dismissManagement()
            sitePermissionsState.coordinator?.pageDidChange(.navigation)
            sitePermissionsState.dismissRecovery()
            sitePermissionsState.bypassPendingBridgeRequests()
            sitePermissionsState.discardPreapprovals()
            return
        }
        sitePermissionsState.mediaCaptureUserScript = userScript
        userScript.delegate = self
    }

    func mediaCaptureUserScript(_ userScript: MediaCaptureUserScript,
                                requestPermissionFor permissionTypes: Set<SitePermissionType>,
                                requestID: String,
                                in frame: WKFrameInfo,
                                webView: WKWebView) async -> MediaCaptureBridgeDecision {
        guard featureFlagger.isFeatureOn(.sitePermissions) else {
            sitePermissionsState.discardPreapprovals()
            return .bypass
        }

        let origin = SitePermissionSecurityOrigin(frame.securityOrigin)
        if origin.host.isDuckAIHost {
            return .bypass
        }

        pruneExpiredMediaCapturePreapprovals()
        guard webView === self.webView,
              !isLinkPreview,
              isMediaCaptureAllowed(for: origin),
              sitePermissionsState.committedMediaPolicyBlocks.isDisjoint(with: permissionTypes),
              sitePermissionsState.pendingBridgeRequests[requestID] == nil,
              !sitePermissionsState.handledBridgeRequestIDs.contains(requestID),
              sitePermissionsState.handledBridgeRequestIDs.count < sitePermissionsState.maximumOutstandingBridgeRequests,
              isSupportedMediaCapturePermissionTypes(permissionTypes),
              let topLevelSite = currentSitePermissionKey(),
              let dependencies = sitePermissionsDependenciesProvider(),
              let coordinator = makeSitePermissionsCoordinatorIfNeeded(dependencies: dependencies) else {
            return .deny
        }
        sitePermissionsState.handledBridgeRequestIDs.insert(requestID)

        let context = SitePermissionRequestContext(
            tabID: tabModel.uid,
            topLevelSite: topLevelSite,
            requestingFrameID: UInt64(UInt(bitPattern: ObjectIdentifier(frame))),
            webContentProcessGeneration: sitePermissionsState.webContentProcessGeneration,
            navigationGeneration: sitePermissionsState.navigationGeneration
        )

        return await withCheckedContinuation { continuation in
            sitePermissionsState.pendingBridgeRequests[requestID] = SitePermissionsState.PendingBridgeRequest(
                context: context,
                frame: frame,
                permissionTypes: permissionTypes,
                origin: origin,
                webViewID: ObjectIdentifier(webView),
                continuation: continuation
            )
            coordinator.request(
                SitePermissionRequest(context: context, permissionTypes: permissionTypes),
                promptHandler: sitePermissionsPromptHandler(),
                completion: { [weak self] resolution in
                    self?.resolveMediaCaptureBridgeRequest(requestID, resolution: resolution)
                }
            )
        }
    }

    private func resolveMediaCaptureBridgeRequest(_ requestID: String,
                                                  resolution: SitePermissionResolution) {
        guard let pendingRequest = sitePermissionsState.pendingBridgeRequests[requestID] else { return }
        guard featureFlagger.isFeatureOn(.sitePermissions) else {
            sitePermissionsState.pendingBridgeRequests[requestID] = nil
            sitePermissionsState.handledBridgeRequestIDs.remove(requestID)
            let decision: MediaCaptureBridgeDecision
            if case .deny = resolution {
                decision = .deny
            } else {
                decision = .bypass
            }
            pendingRequest.continuation.resume(returning: decision)
            return
        }

        guard resolution == .grant,
              currentSitePermissionContext(tabID: pendingRequest.context.tabID,
                                           requestingFrameID: pendingRequest.context.requestingFrameID) == pendingRequest.context,
              let webView,
              ObjectIdentifier(webView) == pendingRequest.webViewID else {
            sitePermissionsState.pendingBridgeRequests[requestID] = nil
            sitePermissionsState.handledBridgeRequestIDs.remove(requestID)
            pendingRequest.continuation.resume(returning: .deny)
            return
        }

        sitePermissionsState.pendingBridgeRequests[requestID] = nil
        sitePermissionsState.mediaCapturePreapprovals.append(SitePermissionsState.MediaCapturePreapproval(
            requestID: requestID,
            permissionTypes: pendingRequest.permissionTypes,
            origin: pendingRequest.origin,
            isMainFrame: pendingRequest.frame.isMainFrame,
            webViewID: pendingRequest.webViewID,
            webContentProcessGeneration: pendingRequest.context.webContentProcessGeneration,
            navigationGeneration: pendingRequest.context.navigationGeneration,
            createdAtUptime: sitePermissionsUptimeProvider()
        ))
        pendingRequest.continuation.resume(returning: .allow)
    }

    private func isSupportedMediaCapturePermissionTypes(_ permissionTypes: Set<SitePermissionType>) -> Bool {
        permissionTypes == [.camera]
            || permissionTypes == [.microphone]
            || permissionTypes == [.camera, .microphone]
    }

    private func isMediaCaptureAllowed(for origin: SitePermissionSecurityOrigin) -> Bool {
        guard origin.isPotentiallyTrustworthy,
              let committedURL = sitePermissionsState.committedMainFrameURL,
              let topLevelOrigin = SitePermissionSecurityOrigin(committedURL) else {
            return false
        }
        return origin == topLevelOrigin
    }

    func captureSitePermissionsMediaPolicy(from response: URLResponse, isForMainFrame: Bool) {
        guard isForMainFrame, sitePermissionsState.isMainFrameNavigationProvisional else { return }
        let header = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Permissions-Policy")
        sitePermissionsState.provisionalMediaPolicyBlocks = Self.mediaTypesDisabledByPermissionsPolicy(header)
    }

    static func mediaTypesDisabledByPermissionsPolicy(_ header: String?) -> Set<SitePermissionType> {
        guard let header else { return [] }
        var blocked = Set<SitePermissionType>()
        for directive in header.split(separator: ",", omittingEmptySubsequences: false) {
            let components = directive.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard components.count == 2 else { continue }
            let name = components[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = components[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard value.first == "(", value.last == ")",
                  value.dropFirst().dropLast().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            if name == "camera" {
                blocked.insert(.camera)
            } else if name == "microphone" {
                blocked.insert(.microphone)
            }
        }
        return blocked
    }
}
