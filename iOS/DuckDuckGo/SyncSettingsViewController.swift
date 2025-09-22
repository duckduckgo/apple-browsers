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
import os.log
import BrowserServicesKit

@MainActor
class SyncSettingsViewController: UIHostingController<SyncSettingsView> {

    struct Constants {
        static let startSyncFlow = "sync-start"
        static let startBackupFlow = "sync-backup"
    }

    lazy var authenticator = Authenticator()
    lazy var connectionController: SyncConnectionControlling = syncService.createConnectionController(deviceName: deviceName, deviceType: deviceType, delegate: self)

    let syncService: DDGSyncing
    let syncBookmarksAdapter: SyncBookmarksAdapter
    let syncCredentialsAdapter: SyncCredentialsAdapter
    var connector: RemoteConnecting?

    let userAuthenticator = UserAuthenticator(reason: UserText.syncUserUserAuthenticationReason,
                                              cancelTitle: UserText.autofillLoginListAuthenticationCancelButton)
    let userSession = UserSession()
    let featureFlagger: FeatureFlagger
    
    var isSyncEnabled: Bool {
        syncService.account != nil
    }

    var recoveryCode: String {
        guard let code = syncService.account?.recoveryCode else {
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
    var viewModel: SyncSettingsViewModel?

    var source: String?
    var pairingInfo: PairingInfo?

    var onConfirmSyncDisable: (() -> Void)?
    var onConfirmAndDeleteAllData: (() -> Void)?

    // For some reason, on iOS 14, the viewDidLoad wasn't getting called so do some setup here
    init(
        syncService: DDGSyncing,
        syncBookmarksAdapter: SyncBookmarksAdapter,
        syncCredentialsAdapter: SyncCredentialsAdapter,
        appSettings: AppSettings = AppDependencyProvider.shared.appSettings,
        syncPausedStateManager: any SyncPausedStateManaging,
        source: String? = nil,
        pairingInfo: PairingInfo? = nil,
        featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger
    ) {
        self.syncService = syncService
        self.syncBookmarksAdapter = syncBookmarksAdapter
        self.syncCredentialsAdapter = syncCredentialsAdapter
        self.syncPausedStateManager = syncPausedStateManager
        self.source = source
        self.pairingInfo = pairingInfo
        self.featureFlagger = featureFlagger

        let viewModel = SyncSettingsViewModel(
            isOnDevEnvironment: { syncService.serverEnvironment == .development },
            switchToProdEnvironment: {
                syncService.updateServerEnvironment(.production)
                UserDefaults.standard.set(ServerEnvironment.production.description, forKey: UserDefaultsWrapper<String>.Key.syncEnvironment.rawValue)
            }
        )
        self.viewModel = viewModel

        super.init(rootView: SyncSettingsView(model: viewModel))

        setUpFaviconsFetcherSwitch(viewModel)
        setUpFavoritesDisplayModeSwitch(viewModel, appSettings)
        setUpSyncPaused(viewModel, syncPausedStateManager: syncPausedStateManager)
        setUpSyncInvalidObjectsInfo(viewModel)
        setUpSyncFeatureFlags(viewModel)
        refreshForState(syncService.authState)

        syncService.authStatePublisher
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] authState in
                self?.refreshForState(authState)
            }
            .store(in: &cancellables)

        rootView.model.delegate = self
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
            .map { $0.truncated(length: 15) } ?? []

        let invalidCredentialsObjects: [String] = (try? syncCredentialsAdapter.provider?.fetchDescriptionsForObjectsThatFailedValidation()) ?? []
        viewModel.invalidCredentialsTitles = invalidCredentialsObjects.map({ $0.truncated(length: 15) })
    }


    override func viewDidLoad() {
        super.viewDidLoad()
        decorate()
        startSyncWithAnotherDeviceIfNecessary()
        startSyncBackupIfNecessary()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        connector = nil
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

    func refreshForState(_ authState: SyncAuthState) {
        rootView.model.isSyncEnabled = authState != .inactive
        if authState != .inactive {
            rootView.model.syncEnabled(recoveryCode: recoveryCode)
            refreshDevices()
        }
    }

    func dismissPresentedViewController(completion: (() -> Void)? = nil) {
        rootView.model.isSyncWithSetUpSheetVisible = false
        guard let presentedViewController = navigationController?.presentedViewController,
              !(presentedViewController is UIHostingController<SyncSettingsView>) else {
            completion?()
            return
        }
        presentedViewController.dismiss(animated: true, completion: completion)
        endConnectMode()
    }

    func refreshDevices(clearDevices: Bool = true) {
        guard syncService.authState != .inactive else { return }

        Task { @MainActor in
            if clearDevices {
                rootView.model.devices = []
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
        rootView.model.devices = devices.map {
            .init(id: $0.id, name: $0.name, type: $0.type, isThisDevice: $0.id == syncService.account?.deviceId)
        }.sorted(by: { lhs, _ in
            lhs.isThisDevice
        })
    }

    private func startPairingIfNecessary() {
        if let pairingInfo {
            askForPairingConfirmation(deviceName: pairingInfo.deviceName)
        }
    }

    private func startSyncWithAnotherDeviceIfNecessary() {
        guard source == Constants.startSyncFlow,
              syncService.account == nil else {
            return
        }

        Task { @MainActor in
            do {
                try await authenticateUser()
                showSyncWithAnotherDevice()
            }
        }
    }

    private func startSyncBackupIfNecessary() {
        guard source == Constants.startBackupFlow,
              syncService.account == nil else {
            return
        }

        Task { @MainActor in
            await rootView.model.presentSyncWithSetUpSheetIfNeeded()
        }
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.dismissVCAndShowRecoveryPDF()
        }
    }

    func startPolling() {
        Task { @MainActor in
            do {
                if let recoveryKey = try await connector?.pollForRecoveryKey() {
                    dismissPresentedViewController()
                    showPreparingSync(nil)
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

        return await connectionController.syncCodeEntered(code: code, canScanURLBarcodes: featureFlagger.isFeatureOn(.canScanUrlBasedSyncSetupBarcodes), codeSource: codeSource)
    }

    func dismissVCAndShowRecoveryPDF() {
        self.navigationController?.topViewController?.dismiss(animated: true, completion: self.showRecoveryPDF)
    }

    func codeCollectionCancelled() {
        assert(navigationController?.visibleViewController is UIHostingController<AnyView>)
        dismissPresentedViewController()
        Pixel.fire(pixel: .syncSetupEndedAbandoned)
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
        self.rootView.model.$devices
            .removeDuplicates()
            .dropFirst()
            .prefix(1)
            .sink { [weak self] _ in
                guard let self else { return }
                self.dismissVCAndShowRecoveryPDF()
            }.store(in: &cancellables)
    }
    
    func controllerDidCreateSyncAccount() {
        let additionalParameters = source.map { ["source": $0] } ?? [:]
        Pixel.fire(pixel: .syncSignupConnect, withAdditionalParameters: additionalParameters, includedParameters: [.appVersion])
        self.dismissVCAndShowRecoveryPDF()
        rootView.model.syncEnabled(recoveryCode: recoveryCode)
    }
    
    func controllerWillBeginTransmittingRecoveryKey() async {
        dismissPresentedViewController()
        await showPreparingSync()
    }
    
    func controllerDidFinishTransmittingRecoveryKey() {
        dismissPresentedViewController()
    }
    
    func controllerDidReceiveRecoveryKey() {
        dismissPresentedViewController()
        showPreparingSync(nil)
    }
    
    func controllerDidRecognizeCode(setupSource: SyncSetupSource, codeSource: SyncCodeSource) async {
        sendCodeRecognisedPixel(setupSource: setupSource, codeSource: codeSource)
        dismissPresentedViewController()
        await showPreparingSync()
    }
    
    func controllerDidFindTwoAccountsDuringRecovery(_ recoveryKey: SyncCode.RecoveryKey, setupRole: SyncSetupRole) async {
        if rootView.model.devices.count > 1 {
            promptToSwitchAccounts(recoveryKey: recoveryKey)
        } else {
            await switchAccounts(recoveryKey: recoveryKey)
        }
    }
    
    func controllerDidCompleteLogin(registeredDevices: [RegisteredDevice], isRecovery: Bool, setupRole: SyncSetupRole) {
        mapDevices(registeredDevices)
        Pixel.fire(pixel: .syncLogin, includedParameters: [.appVersion])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.dismissVCAndShowRecoveryPDF()
        }
        guard case .receiver(let syncSetupSource, let syncCodeSource) = setupRole else {
            return
        }

        sendSetupEndedSuccessfullyPixel(setupSource: syncSetupSource, codeSource: syncCodeSource)
    }
    
    func controllerDidError(_ error: SyncConnectionError, underlyingError: (any Error)?, setupRole: SyncSetupRole) async {
        switch error {
        case .unableToRecognizeCode:
            sendCodeParsingFailedPixel(setupRole: setupRole)
            await handleError(.unableToRecognizeCode, error: underlyingError, event: nil)
        case .failedToFetchPublicKey, .failedToTransmitExchangeRecoveryKey, .failedToFetchConnectRecoveryKey, .failedToLogIn, .failedToTransmitExchangeKey, .failedToFetchExchangeRecoveryKey, .failedToTransmitConnectRecoveryKey:
            await handleError(.unableToSyncWithDevice, error: underlyingError, event: .syncLoginError)
        case .failedToCreateAccount:
            await handleError(.unableToSyncWithDevice, error: underlyingError, event: .syncSignupError)
        case .pollingForRecoveryKeyTimedOut:
            dismissPresentedViewController()
            handleRecoveryKeyPollingTimeout(setupRole: setupRole)
        }
    }

    private func sendCodeRecognisedPixel(setupSource: SyncSetupSource, codeSource: SyncCodeSource) {
        guard setupSource != .recovery, setupSource != .unknown else { return }
        let parameters = source.map { [PixelParameters.source: $0] } ?? [PixelParameters.source: setupSource.rawValue]
        switch codeSource {
        case .qrCode:
            Pixel.fire(pixel: .syncSetupBarcodeScannerSuccess, withAdditionalParameters: parameters, includedParameters: [.appVersion])
        case .pastedCode:
            Pixel.fire(pixel: .syncSetupManualCodeEnteredSuccess, withAdditionalParameters: parameters, includedParameters: [.appVersion])
        case .deepLink:
            break
        }
    }

    private func sendCodeParsingFailedPixel(setupRole: SyncSetupRole) {
        guard case .receiver(_, let codeSource) = setupRole else {
            return
        }

        switch codeSource {
        case .qrCode:
            Pixel.fire(pixel: .syncSetupBarcodeScannerFailed, includedParameters: [.appVersion])
        case .pastedCode:
            Pixel.fire(pixel: .syncSetupManualCodeEnteredFailed, includedParameters: [.appVersion])
        case .deepLink:
            break
        }
    }

    private func sendSetupEndedSuccessfullyPixel(setupSource: SyncSetupSource, codeSource: SyncCodeSource) {
        guard setupSource != .recovery, setupSource != .unknown else { return }
        let parameters = source.map { [PixelParameters.source: $0] } ?? [PixelParameters.source: setupSource.rawValue]
        switch codeSource {
        case .pastedCode, .qrCode:
            Pixel.fire(pixel: .syncSetupEndedSuccessful, withAdditionalParameters: parameters, includedParameters: [.appVersion])
        case .deepLink:
            Pixel.fire(pixel: .syncSetupDeepLinkFlowSuccess, includedParameters: [.appVersion])
        }
    }

    private func handleRecoveryKeyPollingTimeout(setupRole: SyncSetupRole) {
        guard case .receiver(let setupSource, let codeSource) = setupRole else {
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
