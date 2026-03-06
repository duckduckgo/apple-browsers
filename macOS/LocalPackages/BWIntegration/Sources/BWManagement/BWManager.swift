//
//  BWManager.swift
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

import AppKit
import BWIntegration
import BWManagementShared
import Common
import Foundation
import os.log
import PixelKit
import SwiftUI

final class BWManager: BWManagement, ObservableObject {

    static let bundleId = "com.bitwarden.desktop"
    static let applicationName = "Bitwarden"
    static let applicationPath = "/Applications/Bitwarden.app/Contents/MacOS/Bitwarden"
    static let arguments = ["chrome-extension://bitwarden"]

    private let pixelFiring: PixelFiring?
    private let isBitwardenPasswordManagerProvider: () -> Bool
    private let showRestartBitwardenAlert: (@escaping () -> Void) -> Void

    private let communicator: NativeMessagingCommunication

    init(communicator: NativeMessagingCommunication? = nil,
         pixelFiring: PixelFiring? = PixelKit.shared,
         isBitwardenPasswordManagerProvider: @escaping () -> Bool = { false },
         showRestartBitwardenAlert: @escaping (@escaping () -> Void) -> Void = { _ in }) {
        self.communicator = communicator ?? NativeMessagingCommunicator(appPath: Self.applicationPath, arguments: Self.arguments)
        self.pixelFiring = pixelFiring
        self.isBitwardenPasswordManagerProvider = isBitwardenPasswordManagerProvider
        self.showRestartBitwardenAlert = showRestartBitwardenAlert
    }

    func initCommunication() {
        communicator.delegate = self

        connectToBitwardenProcess()
    }

    func cancelCommunication() {
        connectionAttemptTimer?.invalidate()
        connectionAttemptTimer = nil
        status = .disabled
        communicator.terminateProxyProcess()
        try? keyStorage.cleanSharedKey()
        encryption.cleanKeys()
    }

    // MARK: - Installation

    let installationService: BWInstallationService = LocalBitwardenInstallationService()

    func openBitwarden() {
        installationService.openBitwarden()
    }

    private func restartBitwarden() {
        let runningApplications = NSWorkspace.shared.runningApplications
        let bitwarden = runningApplications.first { runningApplication in
            runningApplication.bundleIdentifier == Self.bundleId
        }

        bitwarden?.terminate()

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleId) {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            }
        }
    }

    // MARK: - Connection

    var isBitwardenPasswordManager: Bool {
        isBitwardenPasswordManagerProvider()
    }

    private func connectToBitwardenProcess() {
        // Check preferences to make sure Bitwarden is set as password manager
        guard isBitwardenPasswordManager else {
            // The built-in password manager is used
            return
        }

        // Check whether Bitwarden is installed and make sure it supports the integration
        switch installationService.installationState {
        case .notInstalled:
            status = .notInstalled
            scheduleConnectionAttempt()
            return
        case .oldVersion:
            status = .oldVersion
            scheduleConnectionAttempt()
            return
        case .incompatible:
            status = .incompatible
            scheduleConnectionAttempt()
            return
        case .installed:
            break
        }

        // Check whether Bitwarden app is running
        guard RunningApplicationCheck.isApplicationRunning(bundleId: Self.bundleId) else {
            status = .notRunning
            scheduleConnectionAttempt()
            return
        }

        // Check wether user approved access to sandbox containers
        guard installationService.isSandboxContainerAccessApproved else {
            status = .accessToContainersNotApproved
            scheduleConnectionAttempt()
            return
        }

        // Check whether user approved integration with DuckDuckGo in Bitwarden
        guard installationService.isIntegrationWithDuckDuckGoEnabled else {
            status = .integrationNotApproved
            scheduleConnectionAttempt()
            return
        }

        // Check wheter the onboarding flow finished successfully
        let sharedKey = try? keyStorage.retrieveSharedKey()
        if sharedKey == nil {
            // The onboarding flow wasn't finished successfully
            status = .missingHandshake
        } else {
            status = .connecting
        }

        // Run the proxy process
        do {
            try communicator.runProxyProcess()
        } catch {
            Logger.bitWarden.error("BWManagement: Running of proxy process failed")
            pixelFiring?.fire(DebugEvent(BWManagementPixels.bitwardenNotResponding))
            status = .error(error: .runningOfProxyProcessFailed)
            scheduleConnectionAttempt()
        }
    }

    private var connectionAttemptTimer: Timer?

    // Disables communicator (kills the proxy process)
    // and schedules future attempt to connect
    private func scheduleConnectionAttempt() {
        guard connectionAttemptTimer == nil else {
            // Already scheduled
            return
        }

        connectionAttemptTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { [weak self] _ in
            self?.connectionAttemptTimer?.invalidate()
            self?.connectionAttemptTimer = nil

            self?.connectToBitwardenProcess()
        }
    }

    private func cancelConnectionAndScheduleNextAttempt() {
        // Kill the proxy process and schedule the next attempt
        communicator.terminateProxyProcess()
        scheduleConnectionAttempt()
    }

    // MARK: - Status Refreshing

    private var statusRefreshingTimer: Timer?

    // Disables communicator (kills the proxy process)
    // and schedules future attempt to connect
    private func scheduleStatusRefreshing() {
        guard statusRefreshingTimer == nil else {
            // Already scheduled
            return
        }

        statusRefreshingTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.sendStatus()
        }
    }

    private func stopStatusRefreshing() {
        statusRefreshingTimer?.invalidate()
        statusRefreshingTimer = nil
    }

    // MARK: - Handling Incoming Messages

    private func handleCommand(_ command: BWCommand) {
        switch command {
        case .connected:
            let sharedKey: Base64EncodedString?
            do {
                sharedKey = try keyStorage.retrieveSharedKey()
            } catch {
                status = .handshakeNotApproved
                assertionFailure("Failed to retrieve shared key")
                return
            }

            // If shared key retrieval is successfull, we already onboarded the user.
            if let sharedKey = sharedKey {
                guard let sharedKeyData = Data(base64Encoded: sharedKey),
                      encryption.setSharedKey(sharedKeyData) else {
                    pixelFiring?.fire(DebugEvent(BWManagementPixels.bitwardenSharedKeyInjectionFailed))
                    status = .error(error: .sharedKeyInjectionFailed)
                    return
                }
                status = .waitingForStatusResponse

                verifyBitwardenIsResponding()
                sendStatus()
            } else {
                // Onboarding is in progress
                // Other part of the code is responsible for sending the handshake message
            }
        case .disconnected:
            // Bitwarden application isn't running
            cancelConnectionAndScheduleNextAttempt()
            if status != .disabled {
                status = .notRunning
            }
        default:
            Logger.bitWarden.fault("BWManager: Wrong handler")
            assertionFailure("BWManager: Wrong handler")
        }
    }

    private var verificationTimer: Timer?

    private func verifyBitwardenIsResponding() {
        verificationTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            guard let self else { return }
            verificationTimer?.invalidate()
            verificationTimer = nil

            if status == .waitingForStatusResponse {
                pixelFiring?.fire(DebugEvent(BWManagementPixels.bitwardenNotResponding))
                showRestartBitwardenAlert { [weak self] in
                    self?.restartBitwarden()
                }
            }
        }
    }

    private func handleError(_ error: String) {
        switch error {
        case "cannot-decrypt":
            Logger.bitWarden.fault("BWManagement: Bitwarden error - cannot decrypt")
            assertionFailure("BWManagement: Bitwarden error - cannot decrypt")
            pixelFiring?.fire(DebugEvent(BWManagementPixels.bitwardenRespondedCannotDecrypt), frequency: .legacyDaily)
        case "locked":
            if case let .connected(vault) = status {
                status = .connected(vault: vault.locked)
            } else {
                sendStatus()
            }
            return
        default:
            Logger.bitWarden.fault("BWManager: Unhandled error")
            assertionFailure("BWManager: Unhandled error")
            pixelFiring?.fire(DebugEvent(BWManagementPixels.bitwardenRespondedWithError))
        }
    }

    private func handleHandshakeResponse(encryptedSharedKey: String, status: String) {
        guard status == "success" else {
            pixelFiring?.fire(DebugEvent(BWManagementPixels.bitwardenHandshakeFailed))
            self.status = .error(error: .handshakeFailed)
            cancelConnectionAndScheduleNextAttempt()
            return
        }

        guard let sharedKey = encryption.decryptSharedKey(encryptedSharedKey) else {
            pixelFiring?.fire(DebugEvent(BWManagementPixels.bitwardenDecryptionOfSharedKeyFailed))
            self.status = .error(error: .decryptionOfSharedKeyFailed)
            cancelConnectionAndScheduleNextAttempt()
            return
        }

        do {
            try keyStorage.save(sharedKey: sharedKey)
        } catch {
            pixelFiring?.fire(DebugEvent(BWManagementPixels.bitwardenStoringOfTheSharedKeyFailed))
            self.status = .error(error: .storingOfTheSharedKeyFailed)
            return
        }

        sendStatus()
    }

    private func handleEncryptedResponse(_ encryptedPayload: BWResponse.EncryptedPayload, messageId: MessageId) {
        guard let dataString = encryptedPayload.data,
              let data = Data(base64Encoded: dataString),
              let ivDataString = encryptedPayload.iv,
              let ivData = Data(base64Encoded: ivDataString),
              let hmacString = encryptedPayload.mac,
              let hmac = Data(base64Encoded: hmacString)
        else {
            pixelFiring?.fire(DebugEvent(BWManagementPixels.bitwardenParsingFailed))
            status = .error(error: .parsingFailed)
            return
        }

        // Compare HMAC
        let ourHmac = encryption.computeHmac(data, iv: ivData)
        guard ourHmac == hmac else {
            pixelFiring?.fire(DebugEvent(BWManagementPixels.bitwardenHmacComparisonFailed))
            Logger.bitWarden.fault("BWManager: HMAC comparison failed")
            assertionFailure("BWManager: HMAC comparison failed")
            return
        }

        let decryptedData = encryption.decryptData(data, andIv: ivData)
        guard decryptedData.count > 0 else {
            pixelFiring?.fire(DebugEvent(BWManagementPixels.bitwardenDecryptionFailed))
            status = .error(error: .decryptionOfDataFailed)
            return
        }

        guard let response = BWResponse(from: decryptedData) else {
            pixelFiring?.fire(DebugEvent(BWManagementPixels.bitwardenParsingFailed))
            status = .error(error: .parsingFailed)
            return
        }

        switch response.command {
        case .status:
            if case let .array(payloadItemArray) = response.payload {
                handleStatusResponse(payloadItemArray: payloadItemArray)
                return
            }
        case .credentialRetrieval:
            if let payload = response.payload {
                handleCredentialRetrievalResponse(messageId: messageId, payload: payload)
                return
            }
        case .credentialCreate:
            if case let .item(payloadIdem) = response.payload {
                handleCredentialCreationResponse(messageId: messageId, payloadItem: payloadIdem)
                return
            }
        case .credentialUpdate:
            if case let .item(payloadIdem) = response.payload {
                handleCredentialUpdateResponse(messageId: messageId, payloadItem: payloadIdem)
                return
            }

        default: break
        }

        Logger.bitWarden.fault("BWManager: Unhandled response")
        assertionFailure("BWManager: Unhandled response")
    }

    private func handleStatusResponse(payloadItemArray: [BWResponse.PayloadItem]) {
        // Find the active vault
        guard let activePayloadItem = payloadItemArray.filter({ $0.active ?? false }).first else {
            pixelFiring?.fire(DebugEvent(BWManagementPixels.bitwardenNoActiveVault))
            status = .error(error: .noActiveVault)
            return
        }

        refreshStatus(payloadItem: activePayloadItem)
    }

    private func handleCredentialRetrievalResponse(messageId: MessageId, payload: BWResponse.Payload) {
        guard let (domain, completion) = retrieveCredentialsCompletionCache[messageId] else {
            Logger.bitWarden.fault("BWManager: Missing or already removed completion block")
            assertionFailure("BWManager: Missing or already removed completion block")
            return
        }

        switch payload {
        case .array(let payloadItemArray):
            let credentials = payloadItemArray.compactMap { BWCredential(from: $0, domain: domain) }
            retrieveCredentialsCompletionCache[messageId] = nil
            completion(credentials, nil)
        case .item(let payloadItem):
            guard let error = payloadItem.error else {
                Logger.bitWarden.fault("BWManager: Unexpected response in credential retrieval")
                assertionFailure("BWManager: Unexpected response in credential retrieval")
                return
            }

            handleError(error)
            pixelFiring?.fire(DebugEvent(BWManagementPixels.bitwardenCredentialRetrievalFailed))
            completion([], BWError.credentialRetrievalFailed)
        }
    }

    private func handleCredentialCreationResponse(messageId: MessageId, payloadItem: BWResponse.PayloadItem) {

        guard let completion = createCredentialCompletionCache[messageId] else {
            Logger.bitWarden.fault("BWManager: Missing completion block")
            assertionFailure("BWManager: Missing completion block")
            return
        }
        createCredentialCompletionCache[messageId] = nil

        if payloadItem.status == "success" {
            completion(nil)
        } else {
            pixelFiring?.fire(DebugEvent(BWManagementPixels.bitwardenCredentialCreationFailed))
            completion(BWError.credentialCreationFailed)
        }
    }

    private func handleCredentialUpdateResponse(messageId: MessageId, payloadItem: BWResponse.PayloadItem) {

        guard let completion = updateCredentialCompletionCache[messageId] else {
            Logger.bitWarden.fault("BWManager: Missing completion block")
            assertionFailure("BWManager: Missing completion block")
            return
        }
        updateCredentialCompletionCache[messageId] = nil

        if payloadItem.status == "success" {
            completion(nil)
        } else {
            pixelFiring?.fire(DebugEvent(BWManagementPixels.bitwardenCredentialUpdateFailed))
            completion(BWError.credentialUpdateFailed)
        }
    }

    // MARK: - Sending Messages

    lazy var messageIdGenerator = BWMessageIdGenerator()

    func sendHandshake() {
        guard let publicKey = generateKeyPair() else {
            Logger.bitWarden.fault("BWManager: Public key is missing")
            assertionFailure("BWManager: Public key is missing")
            return
        }

        guard let messageData = BWRequest.makeHandshakeRequest(with: publicKey,
                                                               messageId: messageIdGenerator.generateMessageId(),
                                                               applicationName: Self.applicationName).data else {
            Logger.bitWarden.fault("BWManager: Making the handshake message failed")
            assertionFailure("BWManager: Making the handshake message failed")
            return
        }

        communicator.send(messageData: messageData)
    }

    private func sendStatus() {
        guard let commandData = BWRequest.EncryptedCommand(command: .status, payload: nil).data,
              let encryptedCommand = encryptCommandData(commandData),
              let messageData = BWRequest.makeEncryptedCommandRequest(encryptedCommand: encryptedCommand,
                                                                      messageId: messageIdGenerator.generateMessageId()).data else {
            Logger.bitWarden.fault("BWManager: Making the status message failed")
            assertionFailure("BWManager: Making the status message failed")
            pixelFiring?.fire(DebugEvent(BWManagementPixels.bitwardenSendingOfMessageFailed))
            status = .error(error: .sendingOfMessageFailed)
            return
        }

        communicator.send(messageData: messageData)
    }

    private func sendCredentialRetrieval(url: URL, messageId: MessageId) {
        let payload = BWRequest.EncryptedCommand.Payload(uri: url.absoluteString)
        guard let commandData = BWRequest.EncryptedCommand(command: .credentialRetrieval,
                                                           payload: payload).data,
              let encryptedCommand = encryptCommandData(commandData),
              let messageData = BWRequest.makeEncryptedCommandRequest(encryptedCommand: encryptedCommand,
                                                                      messageId: messageId).data else {
            Logger.bitWarden.fault("BWManager: Making the credential retrieval message failed")
            assertionFailure("BWManager: Making the credential retrieval message failed")
            pixelFiring?.fire(DebugEvent(BWManagementPixels.bitwardenSendingOfMessageFailed))
            status = .error(error: .sendingOfMessageFailed)
            return
        }

        communicator.send(messageData: messageData)
    }

    private func sendCredentialCreation(_ credential: BWCredential, messageId: MessageId) {
        let payload = BWRequest.EncryptedCommand.Payload(uri: credential.url,
                                                         userId: credential.userId,
                                                         userName: credential.username,
                                                         password: credential.password,
                                                         name: credential.credentialName)
        guard let commandData = BWRequest.EncryptedCommand(command: .credentialCreate,
                                                           payload: payload).data,
              let encryptedCommand = encryptCommandData(commandData),
              let messageData = BWRequest.makeEncryptedCommandRequest(encryptedCommand: encryptedCommand,
                                                                      messageId: messageId).data else {
            Logger.bitWarden.fault("BWManager: Making the credential creation message failed")
            assertionFailure("BWManager: Making the credential creation message failed")
            pixelFiring?.fire(DebugEvent(BWManagementPixels.bitwardenSendingOfMessageFailed))
            status = .error(error: .sendingOfMessageFailed)
            return
        }

        communicator.send(messageData: messageData)
    }

    private func sendCredentialUpdate(_ credential: BWCredential, messageId: MessageId) {
        let payload = BWRequest.EncryptedCommand.Payload(uri: credential.url,
                                                         userId: credential.userId,
                                                         userName: credential.username,
                                                         password: credential.password,
                                                         name: credential.credentialName,
                                                         credentialId: credential.credentialId)
        guard let commandData = BWRequest.EncryptedCommand(command: .credentialUpdate,
                                                           payload: payload).data,
              let encryptedCommand = encryptCommandData(commandData),
              let messageData = BWRequest.makeEncryptedCommandRequest(encryptedCommand: encryptedCommand,
                                                                      messageId: messageId).data else {
            Logger.bitWarden.fault("BWManager: Making the credential update message failed")
            assertionFailure("BWManager: Making the credential update message failed")
            pixelFiring?.fire(DebugEvent(BWManagementPixels.bitwardenSendingOfMessageFailed))
            status = .error(error: .sendingOfMessageFailed)
            return
        }

        communicator.send(messageData: messageData)
    }

    private func encryptCommandData(_ commandData: Data) -> String? {
        guard let encryptedData = encryption.encryptData(commandData) else {
            return nil
        }

#if DEBUG
        // Verify encryption
        let decryptedData = encryption.decryptData(encryptedData.data, andIv: encryptedData.iv)
        assert(decryptedData.utf8String() != nil)
#endif

        return "2.\(encryptedData.iv.base64EncodedString())|\(encryptedData.data.base64EncodedString())|\(encryptedData.hmac.base64EncodedString())"
    }

    // MARK: - Encryption

    lazy var encryption = BWEncryption()

    private func generateKeyPair() -> Base64EncodedString? {
        return encryption.generateKeys()
    }

    // MARK: - Shared Key Storage

    let keyStorage: BWKeyStoring = BWKeyStorage()

    // MARK: - Status

    @Published private(set) var status: BWStatus = .disabled {
        didSet {
            Logger.bitWarden.log("Status changed: \(String(describing: self.status))")

            // If vault is locked, keep refreshing the latest status
            if case .connected(vault: let vault) = status,
               vault.status == .locked {
                scheduleStatusRefreshing()
            } else {
                stopStatusRefreshing()
            }
            verificationTimer?.invalidate()
            verificationTimer = nil
        }
    }
    var statusPublisher: Published<BWStatus>.Publisher { $status }

    private func refreshStatus(payloadItem: BWResponse.PayloadItem) {
        guard let id = payloadItem.id,
              let email = payloadItem.email,
              let statusString = payloadItem.status,
              let status = BWVault.Status(rawValue: statusString) else {
            pixelFiring?.fire(DebugEvent(BWManagementPixels.bitwardenStatusParsingFailed))
            self.status = .error(error: .statusParsingFailed)
            return
        }

        let vault = BWVault(id: id, email: email, status: status, active: true)
        self.status = .connected(vault: vault)
    }

    func refreshStatusIfNeeded() {
        switch status {
        case .connected, .error: sendStatus()
        default: return
        }
    }

    // MARK: - Cretentials

    // Caches domain and completion handler
    var retrieveCredentialsCompletionCache = [MessageId: (String, ([BWCredential], BWError?) -> Void)]()

    func retrieveCredentials(for url: URL, completion: @escaping ([BWCredential], BWError?) -> Void) {
        let messageId = messageIdGenerator.generateMessageId()
        retrieveCredentialsCompletionCache[messageId] = (url.host ?? "", completion)
        sendCredentialRetrieval(url: url, messageId: messageId)
    }

    var createCredentialCompletionCache = [MessageId: ((BWError?) -> Void)]()

    func create(credential: BWCredential, completion: @escaping (BWError?) -> Void) {
        let messageId = messageIdGenerator.generateMessageId()
        createCredentialCompletionCache[messageId] = completion
        sendCredentialCreation(credential, messageId: messageId)
    }

    var updateCredentialCompletionCache = [MessageId: ((BWError?) -> Void)]()

    func update(credential: BWCredential, completion: @escaping (BWError?) -> Void) {
        let messageId = messageIdGenerator.generateMessageId()
        updateCredentialCompletionCache[messageId] = completion
        sendCredentialUpdate(credential, messageId: messageId)
    }

}

extension BWManager: NativeMessagingCommunicatorDelegate {

    func nativeMessagingCommunicatorProcessDidTerminate(_ bitwardenCommunicator: NativeMessagingCommunication) {
        guard isBitwardenPasswordManager else {
            return
        }

        status = .notRunning

        scheduleConnectionAttempt()
    }

    func nativeMessagingCommunicator(_ bitwardenCommunicator: NativeMessagingCommunication, didReceiveMessageData messageData: Data) {
        guard let response = BWResponse(from: messageData) else {
            Logger.bitWarden.fault("BWManager: Can't decode the message")
            assertionFailure("BWManager: Can't decode the message")
            return
        }

        if let command = response.command, command == .connected || command == .disconnected {
            handleCommand(command)
            return
        }

        guard let messageId = response.messageId, messageIdGenerator.verify(messageId: messageId) else {
            Logger.bitWarden.log("BWManager: Unknown message id. Ignoring the message")
            return
        }

        if case let .item(payloadItem) = response.payload {
            if let error = payloadItem.error {
                handleError(error)
                return
            }

            if let encryptedSharedKey = payloadItem.sharedKey,
               let status = payloadItem.status {
                handleHandshakeResponse(encryptedSharedKey: encryptedSharedKey, status: status)
                return
            }
        }

        if let encryptedPayload = response.encryptedPayload, let messageId = response.messageId {
            handleEncryptedResponse(encryptedPayload, messageId: messageId)
            return
        }

        Logger.bitWarden.fault("BWManager: Unhandled message from Bitwarden")
        assertionFailure("BWManager: Unhandled message from Bitwarden")
    }
}

/// Concrete BWManagement target wiring for the shared factory namespace.
extension BWIntegrationFactory: BWManagementFactory {

    public static func makeManager(isBitwardenPasswordManagerProvider: @escaping () -> Bool,
                                   showRestartBitwardenAlert: @escaping (@escaping () -> Void) -> Void) -> BWManagement {
        BWManager(pixelFiring: PixelKit.shared,
                  isBitwardenPasswordManagerProvider: isBitwardenPasswordManagerProvider,
                  showRestartBitwardenAlert: showRestartBitwardenAlert)
    }

}
