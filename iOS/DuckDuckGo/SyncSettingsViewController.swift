//
//  SyncSettingsViewController.swift
//  DuckDuckGo
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

import SwiftUI
import Core
import Combine
import SyncUI_iOS
import DDGSync
import Common
import FoundationExtensions
import os.log
import PrivacyConfig
import AttributedMetric
import Persistence

@MainActor
class SyncSettingsViewController: UIHostingController<SyncSettingsRootView> {

    struct SourceConstants {
        static let startSyncFlow = "sync-start"
        static let startBackupFlow = "sync-backup"
        static let dataImportSummary = "data_import_summary"
        static let dataImportSummarySyncPromotion = "promotion_data_import_summary"
        static let bookmarksPromotion = "promotion_bookmarks"
        static let passwordsPromotion = "promotion_passwords"
        static let aiChatPromotion = "promotion_ai_chat"
    }

    enum AutoRestorePromptSource: String {
        case syncPairing = "sync_pairing"
        case syncBackup = "sync_backup"
        case syncRecover = "sync_recover"
    }

    lazy var authenticator = Authenticator()
    lazy var connectionController: SyncConnectionControlling = syncService.createConnectionController(deviceName: deviceName, deviceType: deviceType, delegate: self)

    let syncService: DDGSyncing
    let syncBookmarksAdapter: SyncBookmarksAdapter
    let syncCredentialsAdapter: SyncCredentialsAdapter
    let syncCreditCardsAdapter: SyncCreditCardsAdapter?
    var connector: RemoteConnecting?

    let userAuthenticator = UserAuthenticator(reason: UserText.syncUserUserAuthenticationReason,
                                              cancelTitle: UserText.autofillLoginListAuthenticationCancelButton)
    let userSession = UserSession()
    let featureFlagger: FeatureFlagger
    let syncAutoRestoreHandler: SyncAutoRestoreHandling
    let syncSettingsStore: KeyValueStoring

    var isSyncEnabled: Bool {
        syncService.account != nil
    }

    var shouldUsePreservedAccountForConnectionFlow: Bool {
        isSyncEnabled && !needsPreservedAccountCleanupBeforeServerOperation
    }

    var recoveryCode: String {
        guard let code = syncService.recoveryCode else {
            return ""
        }

        return code
    }

    var deviceName: String {
        UIDevice.current.name
    }

    var deviceType: String {
        isPad ? "tablet" : "phone"
    }

    var cancellables = Set<AnyCancellable>()
    let syncPausedStateManager: any SyncPausedStateManaging
    let viewModel: SyncSettingsViewModel

    var source: String?
    var pairingInfo: PairingInfo?
    var pairingV2PeerKind: PairingV2DeviceKind?
    var pairingV2JoinerCodeSource: SyncCodeSource?
    var needsPreservedAccountCleanupBeforeServerOperation = false
    var autoRestorePromptSource: AutoRestorePromptSource?

    var onConfirmAndDeleteAllData: (() -> Void)?

    let useSimplifiedLayoutV2: Bool

    // For some reason, on iOS 14, the viewDidLoad wasn't getting called so do some setup here
    init(
        syncService: DDGSyncing,
        syncBookmarksAdapter: SyncBookmarksAdapter,
        syncCredentialsAdapter: SyncCredentialsAdapter,
        syncCreditCardsAdapter: SyncCreditCardsAdapter?,
        appSettings: AppSettings = AppDependencyProvider.shared.appSettings,
        syncPausedStateManager: any SyncPausedStateManaging,
        source: String? = nil,
        pairingInfo: PairingInfo? = nil,
        featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger,
        syncAutoRestoreHandler: SyncAutoRestoreHandling,
        syncSettingsStore: KeyValueStoring = UserDefaults.standard
    ) {
        self.syncService = syncService
        self.syncBookmarksAdapter = syncBookmarksAdapter
        self.syncCredentialsAdapter = syncCredentialsAdapter
        self.syncCreditCardsAdapter = syncCreditCardsAdapter
        self.syncPausedStateManager = syncPausedStateManager
        self.source = source
        self.pairingInfo = pairingInfo
        self.featureFlagger = featureFlagger
        self.syncAutoRestoreHandler = syncAutoRestoreHandler
        self.syncSettingsStore = syncSettingsStore

        let viewModel = SyncSettingsViewModel(
            isOnDevEnvironment: { syncService.serverEnvironment == .development },
            switchToProdEnvironment: {
                syncService.updateServerEnvironment(.production)
                UserDefaults.standard.set(ServerEnvironment.production.description, forKey: UserDefaultsWrapper<String>.Key.syncEnvironment.rawValue)
            },
            autoRestoreProvider: syncAutoRestoreHandler
        )
        self.viewModel = viewModel

        self.useSimplifiedLayoutV2 = featureFlagger.isFeatureOn(.simplifiedSyncSetupV2)
        let rootView = SyncSettingsRootView(model: viewModel, useSimplifiedLayoutV2: useSimplifiedLayoutV2)

        super.init(rootView: rootView)

        setUpFaviconsFetcherSwitch(viewModel)
        setUpFavoritesDisplayModeSwitch(viewModel, appSettings)
        setUpSyncPaused(viewModel, syncPausedStateManager: syncPausedStateManager)
        setUpSyncInvalidObjectsInfo(viewModel)
        setUpSyncFeatureFlags(viewModel)
        setUpAIChatSyncFeatureFlag(viewModel)
        refreshForState(syncService.authState)

        syncService.authStatePublisher
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] authState in
                self?.refreshForState(authState)
            }
            .store(in: &cancellables)

        viewModel.delegate = self
        navigationItem.title = SyncUI_iOS.UserText.syncTitle
    }
    
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func authenticateUser(completion: @escaping (UserAuthenticator.AuthError?) -> Void) {
        if !userSession.isSessionValid {
            userAuthenticator.logOut()
        }

        userAuthenticator.authenticate { [weak self] error in
            if error == nil {
                self?.userSession.startSession()
            }
            completion(error)
        }
    }

    private func setUpSyncFeatureFlags(_ viewModel: SyncSettingsViewModel) {
        syncService.featureFlagsPublisher.prepend(syncService.featureFlags)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { featureFlags in
                viewModel.isDataSyncingAvailable = featureFlags.contains(.dataSyncing)
                viewModel.isConnectingDevicesAvailable = featureFlags.contains(.connectFlows)
                viewModel.isAccountCreationAvailable = featureFlags.contains(.accountCreation)
                viewModel.isAccountRecoveryAvailable = featureFlags.contains(.accountRecovery)
                viewModel.isAppVersionNotSupported = featureFlags.unavailableReason == .appVersionNotSupported
            }
            .store(in: &cancellables)
    }

    private func setUpAIChatSyncFeatureFlag(_ viewModel: SyncSettingsViewModel) {
        featureFlagger.updatesPublisher
            .prepend(())
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else { return }
                viewModel.isAIChatSyncEnabled = self.featureFlagger.isFeatureOn(.aiChatSync)
            }
            .store(in: &cancellables)
    }

    private func setUpFaviconsFetcherSwitch(_ viewModel: SyncSettingsViewModel) {
        viewModel.isFaviconsFetchingEnabled = syncBookmarksAdapter.isFaviconsFetchingEnabled

        syncBookmarksAdapter.$isFaviconsFetchingEnabled
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { isFaviconsFetchingEnabled in
                if viewModel.isFaviconsFetchingEnabled != isFaviconsFetchingEnabled {
                    viewModel.isFaviconsFetchingEnabled = isFaviconsFetchingEnabled
                }
            }
            .store(in: &cancellables)

        viewModel.$devices
            .map { $0.count > 1 }
            .removeDuplicates()
            .sink { [weak self] hasMoreThanOneDevice in
                self?.syncBookmarksAdapter.isEligibleForFaviconsFetcherOnboarding = hasMoreThanOneDevice
            }
            .store(in: &cancellables)

        viewModel.$isFaviconsFetchingEnabled
            .sink { [weak self] isFaviconsFetchingEnabled in
                self?.syncBookmarksAdapter.isFaviconsFetchingEnabled = isFaviconsFetchingEnabled
                if isFaviconsFetchingEnabled {
                    self?.syncService.scheduler.notifyDataChanged()
                }
            }
            .store(in: &cancellables)
    }

    private func setUpFavoritesDisplayModeSwitch(_ viewModel: SyncSettingsViewModel, _ appSettings: AppSettings) {
        viewModel.isUnifiedFavoritesEnabled = appSettings.favoritesDisplayMode.isDisplayUnified

        viewModel.$isUnifiedFavoritesEnabled.dropFirst().removeDuplicates()
            .sink { [weak self] isEnabled in
                appSettings.favoritesDisplayMode = isEnabled ? .displayUnified(native: .mobile) : .displayNative(.mobile)
                NotificationCenter.default.post(name: AppUserDefaults.Notifications.favoritesDisplayModeChange, object: self)
                self?.syncService.scheduler.notifyDataChanged()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: AppUserDefaults.Notifications.favoritesDisplayModeChange)
            .filter { [weak self] notification in
                guard let viewController = notification.object as? SyncSettingsViewController else {
                    return true
                }
                return viewController !== self
            }
            .receive(on: DispatchQueue.main)
            .sink { _ in
                viewModel.isUnifiedFavoritesEnabled = appSettings.favoritesDisplayMode.isDisplayUnified
            }
            .store(in: &cancellables)
    }

    private func setUpSyncPaused(_ viewModel: SyncSettingsViewModel, syncPausedStateManager: any SyncPausedStateManaging) {
        updateSyncPausedState(viewModel, syncPausedStateManager: syncPausedStateManager)
        syncPausedStateManager.syncPausedChangedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateSyncPausedState(viewModel, syncPausedStateManager: syncPausedStateManager)
            }
            .store(in: &cancellables)
    }

    private func updateSyncPausedState(_ viewModel: SyncSettingsViewModel, syncPausedStateManager: any SyncPausedStateManaging) {
        viewModel.isSyncBookmarksPaused = syncPausedStateManager.isSyncBookmarksPaused
        viewModel.isSyncCredentialsPaused = syncPausedStateManager.isSyncCredentialsPaused
        viewModel.isSyncCreditCardsPaused = syncPausedStateManager.isSyncCreditCardsPaused
        viewModel.isSyncPaused = syncPausedStateManager.isSyncPaused
    }

    private func setUpSyncInvalidObjectsInfo(_ viewModel: SyncSettingsViewModel) {
        syncService.isSyncInProgressPublisher
            .removeDuplicates()
            .filter { !$0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateInvalidObjects(viewModel)
            }
            .store(in: &cancellables)
    }

    private func updateInvalidObjects(_ viewModel: SyncSettingsViewModel) {
        viewModel.invalidBookmarksTitles = syncBookmarksAdapter.provider?
            .fetchDescriptionsForObjectsThatFailedValidation()
            .map { $0.truncated(to: 15, position: .tail) } ?? []

        let invalidCredentialsObjects: [String] = (try? syncCredentialsAdapter.provider?.fetchDescriptionsForObjectsThatFailedValidation()) ?? []
        viewModel.invalidCredentialsTitles = invalidCredentialsObjects.map({ $0.truncated(to: 15, position: .tail) })

        let invalidCreditCardObjects: [String] = (try? syncCreditCardsAdapter?.provider?.fetchDescriptionsForObjectsThatFailedValidation()) ?? []
        viewModel.invalidCreditCardsTitles = invalidCreditCardObjects
    }


    override func viewDidLoad() {
        super.viewDidLoad()
        decorate()
        startSyncWithAnotherDeviceIfNecessary()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        connector = nil
        refreshAutoRestoreDecisionState()
        syncService.scheduler.requestSyncImmediately()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        Pixel.fire(pixel: .settingsSyncOpen, withAdditionalParameters: [
            "is_enabled": isSyncEnabled ? "1" : "0"
        ])

        startPairingIfNecessary()
    }

    func updateOptions() {
        syncService.scheduler.requestSyncImmediately()
    }

    func refreshAutoRestoreDecisionState() {
        viewModel.refreshAutoRestoreDecisionState()
    }

    func refreshForState(_ authState: SyncAuthState) {
        viewModel.isSyncEnabled = authState != .inactive
        if authState != .inactive {
            // Sync auto restore completion is inferred when auth transitions away from `.inactive`,
            // so dismiss the recovering sheet if it is still visible at that point.
            dismissRecoveringDataViewIfPresented()
            viewModel.syncEnabled(recoveryCode: recoveryCode)
            refreshDevices()
        }
    }

    func dismissPresentedViewController(completion: (() -> Void)? = nil) {
        viewModel.isRecoverSyncedDataSheetVisible = false
        guard let presentedViewController = navigationController?.presentedViewController,
              !(presentedViewController is SyncSettingsViewController) else {
            completion?()
            return
        }
        presentedViewController.dismiss(animated: true, completion: completion)
    }

    @MainActor
    func dismissPresentedViewController() async {
        await withCheckedContinuation { continuation in
            dismissPresentedViewController {
                continuation.resume()
            }
        }
    }

    func refreshDevices(clearDevices: Bool = true) {
        guard syncService.authState != .inactive else { return }

        Task { @MainActor in
            if clearDevices {
                viewModel.devices = []
            }

            do {
                let devices = try await syncService.fetchDevices()
                mapDevices(devices)
            } catch {
                // Not displaying error since there is the spinner and it is called every few seconds
                Logger.sync.error("Error: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func mapDevices(_ devices: [RegisteredDevice]) {
        viewModel.devices = devices.map {
            .init(id: $0.id,
                  name: $0.name,
                  type: $0.type,
                  credentialId: $0.credentialId,
                  isThisDevice: $0.id == syncService.account?.deviceId)
        }.sorted(by: { lhs, _ in
            lhs.isThisDevice
        })
        NotificationCenter.default.post(name: .syncDevicesUpdate, object: self, userInfo: [AttributedMetricNotificationParameter.syncCount.rawValue: devices.count])
    }

    private func startPairingIfNecessary() {
        if let pairingInfo {
            if pairingInfo.isPairingV2 {
                startPairingV2DeepLink(pairingInfo)
            } else if isLegacyExchangeDeepLink(pairingInfo) {
                askForPairingConfirmation(deviceName: pairingInfo.deviceName)
            } else {
                // URL-based Sync setup should only accepts legacy v1 exchange codes.
                self.pairingInfo = nil
            }
        }
    }

    private func isLegacyExchangeDeepLink(_ pairingInfo: PairingInfo) -> Bool {
        guard let syncCode = try? SyncCode.decodeBase64String(pairingInfo.base64Code) else {
            return false
        }
        return syncCode.exchangeKey != nil
    }

    private func startSyncWithAnotherDeviceIfNecessary() {
        let autoStartPairingSources = [SourceConstants.startSyncFlow, SourceConstants.aiChatPromotion]
        guard let source, autoStartPairingSources.contains(source),
              syncService.authState == .inactive else {
            return
        }
        viewModel.beginPairingFlow()
    }

    private func askForAuthThenStartPairing() {
        guard let pairingInfo = self.pairingInfo else { return }
        Task {
            do {
                try await authenticateUser()
                await connectionController.startPairingMode(pairingInfo)
            }
        }
        self.pairingInfo = nil
    }

    private func startPairingV2DeepLink(_ pairingInfo: PairingInfo) {
        self.pairingInfo = nil

        Task {
            do {
                try await authenticateUser()
            } catch {
                return
            }

            Pixel.fire(pixel: .syncSetupDeepLinkFlowStarted, includedParameters: [.appVersion])

            await connectionController.syncCodeEntered(
                code: pairingInfo.base64Code,
                canScanLegacyURLBarcodes: featureFlagger.isFeatureOn(.canScanUrlBasedSyncSetupBarcodes),
                codeSource: .deepLink)
        }
    }

    func askForPairingConfirmation(deviceName: String) {
        let alert = UIAlertController(title: UserText.syncAlertSyncNewDeviceTitle,
                                      message: UserText.syncAlertSyncNewDeviceMessage(deviceName),
                                      preferredStyle: .alert)
        let cancelAction = UIAlertAction(title: UserText.actionCancel, style: .cancel) { [weak self] _ in
            self?.handlePairingCancellation()
        }
        let confirmAction = UIAlertAction(title: UserText.syncAlertSyncNewDeviceButton, style: .default) { [weak self] _ in
            self?.handlePairingConfirmation()
        }
        alert.addAction(cancelAction)
        alert.addAction(confirmAction)
        self.present(alert, animated: true)
    }

    private func handlePairingConfirmation() {
        askForAuthThenStartPairing()
        Pixel.fire(pixel: .syncSetupDeepLinkFlowStarted, includedParameters: [.appVersion])
    }

    private func handlePairingCancellation() {
        pairingInfo = nil
        Pixel.fire(pixel: .syncSetupDeepLinkFlowAbandoned, includedParameters: [.appVersion])
    }
}

extension SyncSettingsViewController: ScanOrPasteCodeViewModelDelegate {

    var pasteboardString: String? {
        UIPasteboard.general.string
    }

    func endConnectMode() {
        connector?.stopPolling()
        connector = nil
        Task {
            await connectionController.cancel()
        }
    }

    func startConnectMode() throws -> String {
        // Handle local authentication later
        let connector = try syncService.remoteConnect()
        self.connector = connector
        self.startPolling()
        return connector.code
    }

    func loginAndShowDeviceConnected(recoveryKey: SyncCode.RecoveryKey) async throws {
        let registeredDevices = try await syncService.login(recoveryKey, deviceName: deviceName, deviceType: deviceType)
        mapDevices(registeredDevices)
        Pixel.fire(pixel: .syncLogin, includedParameters: [.appVersion])
        presentSyncCompletionAfterDelay()
    }

    func presentSyncCompletionAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.dismissVCAndShowDeviceSyncedToast()
        }
    }

    func startPolling() {
        Task { @MainActor in
            do {
                if let recoveryKey = try await connector?.pollForRecoveryKey() {
                    await dismissPresentedViewController()
                    await showPreparingSync()
                    try await loginAndShowDeviceConnected(recoveryKey: recoveryKey)
                } else {
                    // Likely cancelled elsewhere
                    return
                }
            } catch {
                await handleError(SyncErrorMessage.unableToSyncWithDevice, error: error, event: .syncLoginError)
            }
        }
    }
    
    func syncCodeEntered(code: String, source: CodeEntrySource) async -> Bool {
        let codeSource: SyncCodeSource
        switch source {
        case .pastedCode:
            codeSource = .pastedCode
        case .qrCode:
            codeSource = .qrCode
        }

        return await connectionController.syncCodeEntered(code: code, canScanLegacyURLBarcodes: featureFlagger.isFeatureOn(.canScanUrlBasedSyncSetupBarcodes), codeSource: codeSource)
    }

    @objc func dismissVCAndShowDeviceSyncedToast() {
        self.navigationController?.topViewController?.dismiss(animated: true) {
            self.enableAutoRestoreByDefaultIfNeeded()
            ActionMessageView.present(message: UserText.simplifiedDeviceSyncedSuccessfullyToast)
        }
    }

    func enableAutoRestoreByDefaultIfNeeded() {
        guard syncAutoRestoreHandler.isAutoRestoreFeatureEnabled,
              syncAutoRestoreHandler.existingDecision() == nil else { return }
        try? syncAutoRestoreHandler.persistDecision(true)
        refreshAutoRestoreDecisionState()
    }

    func codeCollectionCancelled(source: CodeCollectionSource) {
        assert(navigationController?.visibleViewController is UIHostingController<AnyView>)
        needsPreservedAccountCleanupBeforeServerOperation = false
        autoRestorePromptSource = nil
        dismissPresentedViewController()
        endConnectMode()
        Pixel.fire(pixel: .syncSetupEndedAbandoned,
                   withAdditionalParameters: syncSetupPixelParameters(setupSource: SyncSetupSource(codeCollectionSource: source),
                                                                      reason: SyncSetupPixelValue.scanningCancelled),
                   includedParameters: [.appVersion])
    }

    func gotoSettings() {
        if let appSettings = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(appSettings)
        }
    }
}

extension SyncSettingsViewController: SyncConnectionControllerDelegate {

    func controllerDidCompleteAccountConnection(shouldShowSyncEnabled: Bool, setupSource: SyncSetupSource, codeSource: SyncCodeSource) {
        sendSetupEndedSuccessfullyPixel(setupSource: setupSource, codeSource: codeSource)
        guard shouldShowSyncEnabled else { return }
        self.viewModel.$devices
            .removeDuplicates()
            .dropFirst()
            .prefix(1)
            .sink { [weak self] _ in
                guard let self else { return }
                self.dismissVCAndShowDeviceSyncedToast()
            }.store(in: &cancellables)
    }

    func controllerDidCreateSyncAccount(shouldShowSyncEnabled: Bool) {
        let additionalParameters = source.map { ["source": $0] } ?? [:]
        Pixel.fire(pixel: .syncSignupConnect, withAdditionalParameters: additionalParameters, includedParameters: [.appVersion])

        if shouldShowSyncEnabled {
            dismissVCAndShowDeviceSyncedToast()
        }
        viewModel.syncEnabled(recoveryCode: recoveryCode)
    }
    
    func controllerWillBeginTransmittingRecoveryKey() async {
        await dismissPresentedViewController()
        await showPreparingSync()
    }
    
    private func waitForDevicesToChangeThenPresentSyncing() {
        viewModel.$devices
            .removeDuplicates()
            .dropFirst()
            .prefix(1)
            .sink { [weak self] _ in
                guard let self else { return }
                self.dismissVCAndShowDeviceSyncedToast()
            }.store(in: &cancellables)
    }

    func controllerDidFinishTransmittingRecoveryKey(shouldWaitForDevicesToChange: Bool) {
        let parameters = syncSetupPixelParameters(setupSource: .exchange,
                                                  path: SyncSetupPixelValue.pairing,
                                                  peerKind: pairingV2PeerKind?.syncSetupPeerKind,
                                                  myRole: SyncSetupPixelValue.host)
        Pixel.fire(pixel: .syncSetupEndedSuccessful,
                   withAdditionalParameters: parameters,
                   includedParameters: [.appVersion])
        pairingV2PeerKind = nil
        if shouldWaitForDevicesToChange {
            waitForDevicesToChangeThenPresentSyncing()
        } else {
            dismissVCAndShowDeviceSyncedToast()
        }
    }
    
    func controllerDidReceiveRecoveryKey() {
        dismissPresentedViewController { [weak self] in
            self?.showPreparingSync(nil)
        }
    }
    
    func controllerDidRecognizeCode(setupSource: SyncSetupSource, codeSource: SyncCodeSource, codeVersion: SyncSetupCodeVersion) async {
        pairingV2JoinerCodeSource = codeVersion == .v2 && setupSource == .exchange ? codeSource : nil
        sendCodeRecognisedPixel(setupSource: setupSource, codeSource: codeSource, codeVersion: codeVersion)
        await dismissPresentedViewController()
        await showPreparingSync(context: setupSource == .recovery ? .recoveringData : .syncingDevices)
    }

    func controllerWillPerformServerSyncOperation(setupRole _: SyncSetupRole) async -> Bool {
        await performDeferredPreservedAccountCleanupIfNeeded()
    }

    func controllerDidFindTwoAccountsDuringRecovery(_ recoveryKey: SyncCode.RecoveryKey, setupRole: SyncSetupRole, shouldPromptBeforeSwitchingAccounts: Bool) async {
        // For V2 we're intentionally not showing prompt here
        if shouldPromptBeforeSwitchingAccounts && viewModel.devices.count > 1 {
            promptToSwitchAccounts(recoveryKey: recoveryKey)
        } else {
            await switchAccounts(recoveryKey: recoveryKey)
        }
    }
    
    func controllerDidCompleteLogin(registeredDevices: [RegisteredDevice], isRecovery _: Bool, setupRole: SyncSetupRole) {
        mapDevices(registeredDevices)
        Pixel.fire(pixel: .syncLogin, includedParameters: [.appVersion])
        if case .receiver(.recovery, _) = setupRole {
            Task {
                await connectionController.cancel()
            }
        }
        presentSyncCompletionAfterDelay()
        guard case .receiver(let syncSetupSource, let syncCodeSource) = setupRole else {
            // .sharer reaches here only via the connect flow (exchange-sharer terminates in controllerDidFinishTransmittingRecoveryKey).
            let parameters = syncSetupPixelParameters(setupSource: .connect,
                                                      path: SyncSetupPixelValue.pairing,
                                                      peerKind: pairingV2PeerKind?.syncSetupPeerKind,
                                                      myRole: SyncSetupPixelValue.joiner)
            Pixel.fire(pixel: .syncSetupEndedSuccessful,
                       withAdditionalParameters: parameters,
                       includedParameters: [.appVersion])
            pairingV2PeerKind = nil
            return
        }

        sendSetupEndedSuccessfullyPixel(setupSource: syncSetupSource, codeSource: syncCodeSource)
    }

    func controllerDidCompletePairingWithAlreadyConnectedAccount(setupRole: SyncSetupRole) {
        sendSetupEndedFailedPixel(setupRole: setupRole, reason: SyncSetupPixelValue.alreadyPaired)
        Task { @MainActor in
            await handleError(.alreadyPairedWithAccount, error: nil, event: nil)
        }
    }
    
    func controllerDidError(_ error: SyncConnectionError, underlyingError: (any Error)?, setupRole: SyncSetupRole) async {
        switch error {
        case .unableToRecognizeCode:
            sendCodeParsingFailedPixel(setupRole: setupRole, reason: error.syncSetupFailureReason)
            await handleError(.unableToRecognizeCode, error: underlyingError, event: nil)
        case .updateRequired:
            sendCodeParsingFailedPixel(setupRole: setupRole, reason: error.syncSetupFailureReason)
            await handleError(.updateRequired, error: nil, event: nil)
        case .unsupportedThirdPartyRecoveryCode:
            sendCodeParsingFailedPixel(setupRole: setupRole, reason: error.syncSetupFailureReason)
            await handleError(.unsupportedThirdPartyRecoveryCode, error: nil, event: nil)
        case .thirdPartyAccountAlreadyUpgraded:
            sendSetupEndedFailedPixel(setupRole: setupRole, reason: error.syncSetupFailureReason)
            await handleError(.thirdPartyAccountAlreadyUpgraded, error: nil, event: nil)
        case .syncCancelledFromOtherDevice:
            sendSyncConfirmationDeniedSetupEndedAbandonedPixel(setupRole: setupRole)
            await handleError(.syncCancelledFromOtherDevice, error: nil, event: nil)
        case .failedToFetchPublicKey,
                .failedToFetchConnectRecoveryKey,
                .failedToLogIn,
                .failedToTransmitExchangeKey,
                .failedToFetchExchangeRecoveryKey,
                .failedToTransmitConnectRecoveryKey:
            sendSetupEndedFailedPixel(setupRole: setupRole, reason: error.syncSetupFailureReason)
            await handleError(.unableToSyncWithDevice, error: underlyingError, event: .syncLoginError)
        case .failedToTransmitExchangeRecoveryKey:
            sendSetupEndedFailedPixel(setupRole: setupRole, reason: error.syncSetupFailureReason)
            await handleError(.unableToSyncWithDevice, error: underlyingError, event: .syncLoginError)
        case .accountUpgradeFailed,
                .transportFailure,
                .protocolError,
                .unexpectedSecondHello,
                .unexpectedEvent,
                .pairingSessionNotReady,
                .relayChannelUnavailable,
                .recoveryCodePreparationFailed,
                .peerRecoveryCodeUnavailable,
                .unexpectedFailure,
                .missingThirdPartyCredential,
                .undecryptableThirdPartyCredential,
                .accountExtendFailed,
                .missingThirdPartyKey,
                .localStorageFailed,
                .invalidCredentials:
            sendSetupEndedFailedPixel(setupRole: setupRole, reason: error.syncSetupFailureReason)
            await handleError(.unableToSyncWithDevice, error: underlyingError, event: .syncLoginError)
        case .failedToCreateAccount:
            sendSetupEndedFailedPixel(setupRole: setupRole, reason: error.syncSetupFailureReason)
            await handleError(.unableToSyncWithDevice, error: underlyingError, event: .syncSignupError)
        case .accountCreationFailed:
            sendSetupEndedFailedPixel(setupRole: setupRole, reason: error.syncSetupFailureReason)
            await handleError(.unableToSyncWithDevice, error: underlyingError, event: .syncSignupError)
        case .pollingForRecoveryKeyTimedOut:
            sendSetupEndedFailedPixel(setupRole: setupRole, reason: error.syncSetupFailureReason)
            await dismissPresentedViewController()
            handleRecoveryKeyPollingTimeout(setupRole: setupRole)
            await handleError(.unableToSyncWithDevice, error: underlyingError, event: nil)
        case .pairingV2SessionTimedOut:
            sendSetupEndedFailedPixel(setupRole: setupRole, reason: error.syncSetupFailureReason, timeoutStage: error.syncSetupTimeoutStage)
            await dismissPresentedViewController()
            handleRecoveryKeyPollingTimeout(setupRole: setupRole)
            await handleError(.unableToSyncWithDevice, error: underlyingError, event: nil)
        }

    }

    private func sendCodeRecognisedPixel(setupSource: SyncSetupSource, codeSource: SyncCodeSource, codeVersion: SyncSetupCodeVersion) {
        guard setupSource != .unknown else { return }
        let parameters = syncSetupPixelParameters(setupSource: setupSource, codeType: setupSource.syncSetupCodeType, codeVersion: codeVersion.rawValue)
        switch codeSource {
        case .qrCode:
            Pixel.fire(pixel: .syncSetupBarcodeScannerSuccess, withAdditionalParameters: parameters, includedParameters: [.appVersion])
        case .pastedCode:
            Pixel.fire(pixel: .syncSetupManualCodeEnteredSuccess, withAdditionalParameters: parameters, includedParameters: [.appVersion])
        case .deepLink:
            break
        }
    }

    private func sendCodeParsingFailedPixel(setupRole: SyncSetupRole, reason: String?) {
        guard case .receiver(let setupSource, let codeSource) = setupRole else {
            return
        }
        let parameters = syncSetupPixelParameters(setupSource: setupSource, reason: reason)

        switch codeSource {
        case .qrCode:
            Pixel.fire(pixel: .syncSetupBarcodeScannerFailed, withAdditionalParameters: parameters, includedParameters: [.appVersion])
        case .pastedCode:
            Pixel.fire(pixel: .syncSetupManualCodeEnteredFailed, withAdditionalParameters: parameters, includedParameters: [.appVersion])
        case .deepLink:
            break
        }
    }

    private func sendSetupEndedSuccessfullyPixel(setupSource: SyncSetupSource, codeSource: SyncCodeSource) {
        guard setupSource != .unknown else { return }
        let parameters = syncSetupPixelParameters(setupSource: setupSource,
                                                  path: setupSource.syncSetupPath,
                                                  peerKind: pairingV2PeerKind?.syncSetupPeerKind,
                                                  myRole: setupSource.syncSetupMyRole)
        switch codeSource {
        case .pastedCode, .qrCode:
            Pixel.fire(pixel: .syncSetupEndedSuccessful, withAdditionalParameters: parameters, includedParameters: [.appVersion])
            pairingV2PeerKind = nil
        case .deepLink:
            Pixel.fire(pixel: .syncSetupDeepLinkFlowSuccess, includedParameters: [.appVersion])
        }
    }

    private func sendSetupEndedFailedPixel(setupRole: SyncSetupRole, reason: String?, timeoutStage: String? = nil) {
        Pixel.fire(pixel: .syncSetupEndedFailed,
                   withAdditionalParameters: syncSetupPixelParameters(setupRole: setupRole, reason: reason, timeoutStage: timeoutStage),
                   includedParameters: [.appVersion])
        pairingV2PeerKind = nil
    }

    private func sendSetupEndedAbandonedPixel(setupRole: SyncSetupRole, reason: String?) {
        let parameters: [String: String]
        switch setupRole {
        case .receiver(let setupSource, _):
            parameters = syncSetupPixelParameters(setupSource: setupSource, reason: reason)
        case .sharer:
            parameters = syncSetupPixelParameters(setupSource: .exchange, reason: reason)
        }
        Pixel.fire(pixel: .syncSetupEndedAbandoned,
                   withAdditionalParameters: parameters,
                   includedParameters: [.appVersion])
        pairingV2PeerKind = nil
    }

    func sendSyncConfirmationDeniedSetupEndedAbandonedPixel(setupRole: SyncSetupRole) {
        sendSetupEndedAbandonedPixel(setupRole: setupRole, reason: SyncSetupPixelValue.syncConfirmationDenied)
        sendSyncConfirmationDeniedDeepLinkFlowAbandonedPixelIfNeeded(setupRole: setupRole)
    }

    private func sendSyncConfirmationDeniedDeepLinkFlowAbandonedPixelIfNeeded(setupRole: SyncSetupRole) {
        guard case .receiver(_, .deepLink) = setupRole else {
            return
        }
        Pixel.fire(pixel: .syncSetupDeepLinkFlowAbandoned, includedParameters: [.appVersion])
    }

    private func syncSetupPixelParameters(setupRole: SyncSetupRole, reason: String?, timeoutStage: String? = nil) -> [String: String] {
        switch setupRole {
        case .receiver(let setupSource, _):
            return syncSetupPixelParameters(setupSource: setupSource,
                                            path: setupSource.syncSetupPath,
                                            reason: reason,
                                            timeoutStage: timeoutStage,
                                            peerKind: pairingV2PeerKind?.syncSetupPeerKind,
                                            myRole: setupSource.syncSetupMyRole)
        case .sharer:
            return syncSetupPixelParameters(setupSource: .exchange,
                                            path: SyncSetupPixelValue.pairing,
                                            reason: reason,
                                            timeoutStage: timeoutStage,
                                            peerKind: pairingV2PeerKind?.syncSetupPeerKind,
                                            myRole: SyncSetupPixelValue.host)
        }
    }

    private func syncSetupPixelParameters(setupSource: SyncSetupSource,
                                          codeType: String? = nil,
                                          codeVersion: String? = nil,
                                          path: String? = nil,
                                          flowVersion: String? = nil,
                                          reason: String? = nil,
                                          timeoutStage: String? = nil,
                                          peerKind: String? = nil,
                                          myRole: String? = nil) -> [String: String] {
        var parameters = source.map { [PixelParameters.source: $0] } ?? [PixelParameters.source: setupSource.rawValue]
        parameters[SyncSetupPixelParameter.myKind] = SyncSetupPixelValue.ddg
        parameters[SyncSetupPixelParameter.codeType] = codeType
        parameters[SyncSetupPixelParameter.codeVersion] = codeVersion
        parameters[SyncSetupPixelParameter.path] = path
        parameters[SyncSetupPixelParameter.flowVersion] = flowVersion ?? syncSetupPixelFlowVersion
        parameters[SyncSetupPixelParameter.reason] = reason
        parameters[SyncSetupPixelParameter.timeoutStage] = timeoutStage
        parameters[SyncSetupPixelParameter.peerKind] = peerKind
        parameters[SyncSetupPixelParameter.myRole] = myRole
        return parameters
    }

    func fireBarcodeCodeCopiedPixel(for code: String, sourceHint: CodeCollectionSource?) {
        if let url = URL(string: code), PairingInfo.isPairingV2URL(url) {
            let source = sourceHint.map(SyncSetupSource.init(codeCollectionSource:)) ?? .exchange
            Pixel.fire(pixel: .syncSetupBarcodeCodeCopied,
                       withAdditionalParameters: syncSetupPixelParameters(setupSource: source,
                                                                          codeType: SyncSetupPixelValue.linking))
            return
        }

        guard let decoded = try? SyncCode.decodeBase64String(code) else { return }
        let source: SyncSetupSource
        if decoded.connect != nil {
            source = .connect
        } else if decoded.exchangeKey != nil {
            source = .exchange
        } else {
            return
        }
        Pixel.fire(pixel: .syncSetupBarcodeCodeCopied,
                   withAdditionalParameters: syncSetupPixelParameters(setupSource: source,
                                                                      codeType: source.syncSetupCodeType))
    }

    private func handleRecoveryKeyPollingTimeout(setupRole: SyncSetupRole) {
        guard case .receiver(_, let codeSource) = setupRole else {
            return
        }
        guard case .deepLink = codeSource else {
            return
        }
        Pixel.fire(pixel: .syncSetupDeepLinkFlowTimeout, includedParameters: [.appVersion])
    }
}

extension SyncSettingsViewController {

    private func decorate() {
        let theme = ThemeManager.shared.currentTheme
        view.backgroundColor = theme.backgroundColor

        decorateNavigationBar()

    }

}

private enum SyncSetupPixelParameter {
    static let flowVersion = "flow_version"
    static let myKind = "my_kind"
    static let codeType = "code_type"
    static let codeVersion = "code_version"
    static let path = "path"
    static let reason = "reason"
    static let timeoutStage = "timeout_stage"
    static let peerKind = "peer_kind"
    static let myRole = "my_role"
}

private enum SyncSetupPixelValue {
    static let ddg = "ddg"
    static let recovery = "recovery"
    static let pairing = "pairing"
    static let linking = "linking"
    static let scanningCancelled = "scanning_cancelled"
    static let syncConfirmationDenied = "sync_confirmation_denied"
    static let alreadyPaired = "already_paired"
    static let host = "host"
    static let joiner = "joiner"
}

private extension SyncSetupSource {

    init(codeCollectionSource: CodeCollectionSource) {
        switch codeCollectionSource {
        case .connect:
            self = .connect
        case .exchange:
            self = .exchange
        case .recovery:
            self = .recovery
        }
    }

    var syncSetupCodeType: String? {
        switch self {
        case .recovery:
            return SyncSetupPixelValue.recovery
        case .exchange, .connect:
            return SyncSetupPixelValue.linking
        case .unknown:
            return nil
        }
    }

    var syncSetupPath: String? {
        switch self {
        case .recovery:
            return SyncSetupPixelValue.recovery
        case .exchange, .connect:
            return SyncSetupPixelValue.pairing
        case .unknown:
            return nil
        }
    }

    var syncSetupMyRole: String? {
        switch self {
        case .connect:
            return SyncSetupPixelValue.host
        case .exchange:
            return SyncSetupPixelValue.joiner
        case .recovery, .unknown:
            return nil
        }
    }
}

private extension PairingV2DeviceKind {

    var syncSetupPeerKind: String {
        rawValue
    }
}
