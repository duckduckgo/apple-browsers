//
//  SyncSettingsViewModel.swift
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

import Foundation
import UIKit
import Combine

public protocol SyncManagementViewModelDelegate: AnyObject {

    func authenticateUser() async throws
    func showAutoRestoreReady(for continuation: SyncSettingsViewModel.PreservedAccountContinuation)
    func isPreservedAccountPromptNeeded() -> Bool
    func continueAfterPreservedAccountRemoval(_ continuation: SyncSettingsViewModel.PreservedAccountContinuation)
    func showRecoveringDataAutoRestore()
    func showRecoveryCodeEntry()
    func showSyncWithAnotherDevice()
    func shareRecoveryPDF()
    func confirmAndDeleteAllData() async -> Bool
    func confirmRemoveDevice(_ device: SyncSettingsViewModel.Device) async -> Bool
    func removeDevice(_ device: SyncSettingsViewModel.Device)
    func updateDeviceName(_ name: String)
    func refreshDevices(clearDevices: Bool)
    func updateOptions()
    func launchBookmarksViewController()
    func launchAutofillViewController()
    func launchAutofillCreditCardsViewController()
    func showOtherPlatformLinks()
    func fireOtherPlatformLinksPixel(event: SyncSettingsViewModel.PlatformLinksPixelEvent, with source: SyncSettingsViewModel.PlatformLinksPixelSource)
    func fireAutoRestorePixel(event: SyncSettingsViewModel.AutoRestorePixelEvent)
    func fireSyncSetupPixel(event: SyncSettingsViewModel.SyncSetupPixelEvent)
    func shareLink(for url: URL, with message: String, from rect: CGRect)

    // Simplified sync setup experiment
    func simplifiedCreateAccountAndStartSyncing(optionsViewModel: SyncSettingsViewModel)
    func simplifiedConfirmAndDisableSync() async -> Bool
    func simplifiedCopyRecoveryCode()
    func showSimplifiedSyncEnabledToast()
    var hasShownSimplifiedSyncAnotherDevicePrompt: Bool { get set }

    var syncBookmarksPausedTitle: String? { get }
    var syncCredentialsPausedTitle: String? { get }
    var syncCreditCardsPausedTitle: String? { get }
    var syncPausedTitle: String? { get }
    var syncBookmarksPausedDescription: String? { get }
    var syncCredentialsPausedDescription: String? { get }
    var syncCreditCardsPausedDescription: String? { get }
    var syncPausedDescription: String? { get }
    var syncBookmarksPausedButtonTitle: String? { get }
    var syncCredentialsPausedButtonTitle: String? { get }
    var syncCreditCardsPausedButtonTitle: String? { get }
}

public class SyncSettingsViewModel: ObservableObject {

    public enum UserAuthenticationError: Error {
        case authFailed
        case authUnavailable
    }

    public struct Device: Identifiable, Hashable {

        public func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }

        public let id: String
        public let name: String
        public let type: String
        public let credentialId: String?
        public let isThisDevice: Bool

        // Keep these values aligned with DDGSync.SyncCredentialID without coupling SyncUI_iOS to DDGSync.
        public static let defaultCredentialId = "ddg"
        public static let thirdPartyCredentialId = "3party"

        public var isThirdParty: Bool {
            credentialId == Self.thirdPartyCredentialId
        }

        public init(id: String, name: String, type: String, credentialId: String? = nil, isThisDevice: Bool) {
            self.id = id
            self.name = name
            self.type = type
            self.credentialId = credentialId
            self.isThisDevice = isThisDevice
        }

    }

    enum ScannedCodeValidity {
        case invalid
        case valid
    }

    public enum PlatformLinksPixelEvent {
        case appear
        case copy
        case share
    }

    public enum PlatformLinksPixelSource: String {
        case notActivated = "not_activated"
        case activating
        case activated
    }

    public enum AutoRestorePixelEvent {
        case settingsPageShown
        case settingsPageToggleChanged(enabled: Bool)
        case manualRecoveryShown
        case readyRestoreTapped
        case readySkipRestoreTapped
    }

    public enum SyncSetupPixelEvent {
        case backUpThisDeviceTapped
        case signupConfirmedTapped
        case signupAbandoned
        case recoverSyncedDataTapped
        case recoveryConfirmedTapped
    }

    public enum SyncSetupEntryPoint: Equatable {
        case pairing
        case simplifiedToggle
        case simplifiedToggleV2
    }

    public enum PreservedAccountContinuation: Equatable {
        case setup(SyncSetupEntryPoint)
        case recover
    }

    @Published public var isSyncEnabled = false {
        didSet {
            if !isSyncEnabled {
                devices = []
            }
        }
    }

    @Published public var devices = [Device]()
    @Published public var isFaviconsFetchingEnabled = false
    @Published public var isUnifiedFavoritesEnabled = true
    @Published public var isSyncingDevices = false
    @Published public var isSyncPaused = false
    @Published public var isSyncBookmarksPaused = false
    @Published public var isSyncCredentialsPaused = false
    @Published public var isSyncCreditCardsPaused = false
    @Published public var invalidBookmarksTitles: [String] = []
    @Published public var invalidCredentialsTitles: [String] = []
    @Published public var invalidCreditCardsTitles: [String] = []

    @Published public var isBusy = false
    @Published var recoveryCode = ""

    @Published public var isDataSyncingAvailable: Bool = true
    @Published public var isConnectingDevicesAvailable: Bool = true
    @Published public var isAccountCreationAvailable: Bool = true
    @Published public var isAccountRecoveryAvailable: Bool = true
    @Published public var isAIChatSyncEnabled: Bool = false
    @Published public var isAppVersionNotSupported: Bool = false
    @Published public var isRecoverSyncedDataSheetVisible: Bool = false
    @Published public var isSyncWithAnotherDevicePromptVisible: Bool = false

    public enum ConnectingSheetPhase: Equatable, Identifiable {
        case connecting(isRecovery: Bool, isFinishing: Bool = false)
        case syncAnotherDevice(isConnecting: Bool)
        case success(isRecovery: Bool)

        // Constant on purpose: `.sheet(item:)` re-presents whenever the item's identity changes, so a
        // per-case id would dismiss and re-present the sheet on every phase change. A stable id keeps
        // it the same presented sheet, letting the content morph in place; only nil ↔ non-nil presents/dismisses.
        public var id: Int { 0 }
    }

    @Published public var connectingSheetPhase: ConnectingSheetPhase?

    public var isConnectingThisDeviceOnly: Bool {
        connectingSheetPhase == .syncAnotherDevice(isConnecting: true)
    }

    @Published var shouldShowPasscodeRequiredAlert: Bool = false

    public let isAutoRestoreFeatureAvailable: Bool
    @Published public var isAutoRestoreEnabled: Bool = false
    @Published var isAutoRestoreUpdating: Bool = false

    public var autoRestoreStatusText: String {
        isAutoRestoreEnabled ? UserText.autoRestoreStatusOn : UserText.autoRestoreStatusOff
    }

    public weak var delegate: SyncManagementViewModelDelegate?
    private(set) var isOnDevEnvironment: Bool
    private(set) var switchToProdEnvironment: () -> Void = {}
    private var cancellables = Set<AnyCancellable>()
    private var pendingPreservedAccountContinuation: PreservedAccountContinuation?
    private var shouldShowSyncEnabledToastAfterSyncWithAnotherDevicePromptDismissal = false
    private var postConnectingSheetDismissAction: (() -> Void)?

    private let autoRestoreProvider: SyncAutoRestoreProviding

    public init(
        isOnDevEnvironment: @escaping () -> Bool,
        switchToProdEnvironment: @escaping () -> Void,
        autoRestoreProvider: SyncAutoRestoreProviding
    ) {
        self.isOnDevEnvironment = isOnDevEnvironment()
        self.autoRestoreProvider = autoRestoreProvider
        self.isAutoRestoreFeatureAvailable = autoRestoreProvider.isAutoRestoreFeatureEnabled
        if isAutoRestoreFeatureAvailable {
            self.isAutoRestoreEnabled = autoRestoreProvider.existingDecision() ?? false
        }
        self.switchToProdEnvironment = { [weak self] in
            switchToProdEnvironment()
            self?.isOnDevEnvironment = isOnDevEnvironment()
        }
    }

    @MainActor
    func commonAuthenticate() async -> Bool {
        do {
            try await delegate?.authenticateUser()
            return true
        } catch {
            if let error = error as? SyncSettingsViewModel.UserAuthenticationError {
                switch error {
                case .authFailed:
                    break
                case .authUnavailable:
                    shouldShowPasscodeRequiredAlert = true
                }
            }
            return false
        }
    }

    @MainActor
    func requestAutoRestoreUpdate(enabled: Bool) {
        guard enabled != isAutoRestoreEnabled else { return }
        guard !isAutoRestoreUpdating else { return }

        isAutoRestoreUpdating = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isAutoRestoreUpdating = false }

            guard await self.commonAuthenticate() else { return }
            do {
                try self.autoRestoreProvider.persistDecision(enabled)
            } catch {
                return
            }

            self.isAutoRestoreEnabled = enabled
            self.delegate?.fireAutoRestorePixel(event: .settingsPageToggleChanged(enabled: enabled))
        }
    }

    @MainActor
    public func refreshAutoRestoreDecisionState() {
        guard isAutoRestoreFeatureAvailable else {
            isAutoRestoreEnabled = false
            return
        }

        isAutoRestoreEnabled = autoRestoreProvider.existingDecision() == true
    }

    func autoRestoreSettingsPageShown() {
        delegate?.fireAutoRestorePixel(event: .settingsPageShown)
    }

    func autoRestoreManualRecoveryShown() {
        delegate?.fireAutoRestorePixel(event: .manualRecoveryShown)
    }

    func deleteAllData(requireAuthentication: Bool = false) {
        isBusy = true
        Task { @MainActor in
            defer { isBusy = false }
            if requireAuthentication {
                guard await commonAuthenticate() else { return }
            }
            if await delegate!.confirmAndDeleteAllData() {
                isSyncEnabled = false
            }
        }
    }

    func saveRecoveryPDF() {
        Task { @MainActor in
            if await commonAuthenticate() {
                delegate?.shareRecoveryPDF()
            }
        }
    }

    public func scanQRCode() {
        beginPairingFlow()
    }

    public func beginPairingFlow() {
        guard isConnectingDevicesAvailable else { return }
        guard isSyncEnabled || isAccountCreationAvailable else { return }
        Task { @MainActor in
            await beginFlow(for: .setup(.pairing))
        }
    }

    public func beginRecoverFlow() {
        Task { @MainActor in
            guard isAccountRecoveryAvailable else { return }
            await beginFlow(for: .recover)
        }
    }

    @MainActor
    private func beginFlow(for continuation: PreservedAccountContinuation) async {
        guard await commonAuthenticate() else {
            isBusy = false
            return
        }

        guard delegate?.isPreservedAccountPromptNeeded() != true else {
            pendingPreservedAccountContinuation = continuation
            delegate?.showAutoRestoreReady(for: continuation)
            return
        }

        clearPendingPreservedAccountContinuation()
        continueWithoutPreservedAccountPrompt(for: continuation)
    }

    @MainActor
    private func continueWithoutPreservedAccountPrompt(for continuation: PreservedAccountContinuation) {
        switch continuation {
        case .setup(let entryPoint):
            switch entryPoint {
            case .pairing:
                delegate?.showSyncWithAnotherDevice()
            case .simplifiedToggle:
                beginSimplifiedSyncSetup()
            case .simplifiedToggleV2:
                isBusy = false
                connectingSheetPhase = .syncAnotherDevice(isConnecting: false)
            }
        case .recover:
            isRecoverSyncedDataSheetVisible = true
        }
    }

    func createEditDeviceModel(_ device: Device) -> EditDeviceViewModel {
        return EditDeviceViewModel(device: device) { [weak self] newValue in
            self?.delegate?.updateDeviceName(newValue.name)
        }
    }

    func createRemoveDeviceModel(_ device: Device) -> RemoveDeviceViewModel {
        return RemoveDeviceViewModel(device: device) { [weak self] device in
            self?.delegate?.removeDevice(device)
        }
    }

    public func syncEnabled(recoveryCode: String) {
        isBusy = false
        isSyncEnabled = true
        self.recoveryCode = recoveryCode
    }

    public func enableSyncToggleTapped() {
        guard !isBusy else { return }
        guard isAccountCreationAvailable else { return }
        isBusy = true
        Task { @MainActor in
            await beginFlow(for: .setup(.simplifiedToggle))
        }
    }

    public func showSyncAnotherDevicePromptFromToggleV2() {
        guard !isBusy else { return }
        guard isAccountCreationAvailable else { return }
        isBusy = true
        Task { @MainActor in
            await beginFlow(for: .setup(.simplifiedToggleV2))
        }
    }

    @MainActor
    public func beginSimplifiedSyncSetup() {
        guard let delegate else { return }
        isBusy = true
        delegate.simplifiedCreateAccountAndStartSyncing(optionsViewModel: self)
    }

    public func disableSyncToggleTapped() {
        guard !isBusy else { return }
        isBusy = true
        Task { @MainActor in
            defer { isBusy = false }
            if await delegate?.simplifiedConfirmAndDisableSync() == true {
                isSyncEnabled = false
            }
        }
    }

    public var thisDeviceName: String? {
        devices.first(where: { $0.isThisDevice })?.name
    }

    public func shouldShowSyncWithAnotherDevicePrompt() -> Bool {
        guard !isBusy else { return false }
        guard isSyncEnabled else { return false }
        guard devices.count == 1 else { return false }
        guard delegate?.hasShownSimplifiedSyncAnotherDevicePrompt == false else { return false }
        return true
    }

    @discardableResult
    public func checkAndShowSyncWithAnotherDevicePrompt() -> Bool {
        guard shouldShowSyncWithAnotherDevicePrompt() else { return false }
        isSyncWithAnotherDevicePromptVisible = true
        delegate?.hasShownSimplifiedSyncAnotherDevicePrompt = true
        return true
    }

    public func syncAnotherDeviceFromConnectingSheet() {
        postConnectingSheetDismissAction = { [weak self] in
            guard let self else { return }
            guard isConnectingDevicesAvailable else { return }
            guard isSyncEnabled || isAccountCreationAvailable else { return }
            delegate?.showSyncWithAnotherDevice()
        }
        connectingSheetPhase = nil
    }

    @MainActor
    public func syncThisDeviceOnlyFromConnectingSheet() {
        guard !isBusy else { return }
        connectingSheetPhase = .syncAnotherDevice(isConnecting: true)
        beginSimplifiedSyncSetup()
    }

    public func showSuccess(recoveryCode: String, isRecovery: Bool) {
        self.recoveryCode = recoveryCode
        if case .connecting = connectingSheetPhase {
            connectingSheetPhase = .connecting(isRecovery: isRecovery, isFinishing: true)
        } else {
            connectingSheetPhase = .success(isRecovery: isRecovery)
        }
    }

    public func connectingAnimationDidFinish() {
        guard case .connecting(let isRecovery, true) = connectingSheetPhase else { return }
        connectingSheetPhase = .success(isRecovery: isRecovery)
    }

    public func doneFromConnectingSheet() {
        connectingSheetPhase = nil
    }

    public func dismissConnectingSheet(then action: (() -> Void)? = nil) {
        postConnectingSheetDismissAction = action
        connectingSheetPhase = nil
    }

    public func connectingSheetDidDismiss() {
        let action = postConnectingSheetDismissAction
        postConnectingSheetDismissAction = nil
        action?()
    }

    public func dismissSyncWithAnotherDevicePrompt() {
        isSyncWithAnotherDevicePromptVisible = false
    }

    public func syncAnotherDeviceFromPromptTapped() {
        shouldShowSyncEnabledToastAfterSyncWithAnotherDevicePromptDismissal = false
        dismissSyncWithAnotherDevicePrompt()
        scanQRCode()
    }

    public func scheduleSyncEnabledToastAfterSyncWithAnotherDevicePromptDismissal() {
        shouldShowSyncEnabledToastAfterSyncWithAnotherDevicePromptDismissal = true
    }

    public func syncWithAnotherDevicePromptDidDismiss() {
        guard shouldShowSyncEnabledToastAfterSyncWithAnotherDevicePromptDismissal else { return }

        shouldShowSyncEnabledToastAfterSyncWithAnotherDevicePromptDismissal = false
        delegate?.showSimplifiedSyncEnabledToast()
    }

    public func copyCode() {
        Task { @MainActor in
            guard await commonAuthenticate() else { return }
            UIPasteboard.general.string = recoveryCode
        }
    }

    public func simplifiedCopyRecoveryCode() {
        Task { @MainActor in
            guard await commonAuthenticate() else { return }
            delegate?.simplifiedCopyRecoveryCode()
        }
    }

    public func manageBookmarks() {
        delegate?.launchBookmarksViewController()
    }

    public func manageLogins() {
        delegate?.launchAutofillViewController()
    }

    public func manageCreditCards() {
        delegate?.launchAutofillCreditCardsViewController()
    }

    public func shareLinkPressed(for url: URL, with message: String, from rect: CGRect) {
        delegate?.shareLink(for: url, with: message, from: rect)
    }

    public func showOtherPlatformsPressed() {
        delegate?.showOtherPlatformLinks()
    }

    public func fireOtherPlatformLinksPixel(for event: PlatformLinksPixelEvent, source: PlatformLinksPixelSource) {
        delegate?.fireOtherPlatformLinksPixel(event: event, with: source)
    }

    public func startRecoveryCodeEntry() {
        Task { @MainActor in
            guard await commonAuthenticate() else { return }
            delegate?.showRecoveryCodeEntry()
        }
    }

    /// Continue from the authenticated recover sheet without a second auth prompt.
    @MainActor
    public func continueRecoverFlow() {
        delegate?.showRecoveryCodeEntry()
    }

    public func startAutoRestoreSecondaryAction() {
        guard let continuation = pendingPreservedAccountContinuation else {
            assertionFailure("Secondary action fired without pending continuation")
            return
        }
        delegate?.fireAutoRestorePixel(event: .readySkipRestoreTapped)
        clearPendingPreservedAccountContinuation()
        delegate?.continueAfterPreservedAccountRemoval(continuation)
    }

    public func startAutoRestore() {
        Task { @MainActor in
            delegate?.fireAutoRestorePixel(event: .readyRestoreTapped)
            guard await commonAuthenticate() else { return }
            clearPendingPreservedAccountContinuation()
            delegate?.showRecoveringDataAutoRestore()
        }
    }

    public func clearPendingPreservedAccountContinuation() {
        pendingPreservedAccountContinuation = nil
    }

    public var syncBookmarksPausedTitle: String? {
        return delegate?.syncBookmarksPausedTitle
    }
    public var syncCredentialsPausedTitle: String? {
        delegate?.syncCredentialsPausedTitle
    }
    public var syncCreditCardsPausedTitle: String? {
        delegate?.syncCreditCardsPausedTitle
    }
    public var syncPausedTitle: String? {
        delegate?.syncPausedTitle
    }
    public var syncBookmarksPausedDescription: String? {
        delegate?.syncBookmarksPausedDescription
    }
    public var syncCredentialsPausedDescription: String? {
        delegate?.syncCredentialsPausedDescription
    }
    public var syncCreditCardsPausedDescription: String? {
        delegate?.syncCreditCardsPausedDescription
    }
    public var syncPausedDescription: String? {
        delegate?.syncPausedDescription
    }
    public var syncBookmarksPausedButtonTitle: String? {
        delegate?.syncBookmarksPausedButtonTitle
    }
    public var syncCredentialsPausedButtonTitle: String? {
        delegate?.syncCredentialsPausedButtonTitle
    }
    public var syncCreditCardsPausedButtonTitle: String? {
        delegate?.syncCreditCardsPausedButtonTitle
    }
}

public extension SyncManagementViewModelDelegate {
    func fireAutoRestorePixel(event _: SyncSettingsViewModel.AutoRestorePixelEvent) {}
    func fireSyncSetupPixel(event _: SyncSettingsViewModel.SyncSetupPixelEvent) {}
    func simplifiedCopyRecoveryCode() {}
    func showSimplifiedSyncEnabledToast() {}
}
