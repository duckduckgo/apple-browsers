//
//  BitwardenNativeMessagingHandler.swift
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

#if WEB_EXTENSIONS_ENABLED

import Foundation
import os.log
import WebKit
import LocalAuthentication

@available(macOS 15.4, *)
final class BitwardenNativeMessagingHandler: NativeMessagingHandling {

    var nativeMessagingConnections = [NativeMessagingConnection]()
    var comm1: NativeMessagingCommunicator?

    func handleMessage(_ message: Any, to applicationIdentifier: String?, for extensionContext: WKWebExtensionContext) throws -> Any? {

        if let message = message as? [String: Any] {
            switch applicationIdentifier {
            case "com.bitwarden.desktop", "com.8bit.bitwarden":
                guard let command = message["command"] as? String else {
                    throw NSError(domain: "NativeMessagingHandler", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing 'command' field in the message"])
                }

                // Extract messageId for response
                let messageId = message["messageId"] as? Int ?? 0

                switch command {
                case "copyToClipboard":
                    guard let string = message["data"] as? String else {
                        throw NSError(domain: "NativeMessagingHandler", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing 'data' field in the message"])
                    }

                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(string, forType: .string)
                    return [
                        "messageId": messageId,
                        "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
                        "success": true
                    ]
                case "getBiometricsStatusForUser":
                    let result = getBiometricsStatusForUser(extensionContext: extensionContext, messageId: messageId)
                    print("[BitwardenNativeMessaging] getBiometricsStatusForUser returning: \(result)")
                    return result
                case "getBiometricsStatus":
                    let result = [
                        "messageId": messageId,
                        "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
                        "response": 0
                    ] as [String: Any]
                    print("[BitwardenNativeMessaging] getBiometricsStatus returning: \(result)")
                    return result
                case "unlockWithBiometricsForUser":
                    guard let userId = message["userId"] as? String else {
                        return [
                            "messageId": messageId,
                            "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
                            "error": "Missing userId"
                        ]
                    }
                    return unlockWithBiometricsForUser(userId: userId, messageId: messageId)
                case "sleep":
                    return [
                        "messageId": messageId,
                        "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
                        "success": true
                    ]
                default:
                    print("[BitwardenNativeMessaging] Unhandled command: \(command)")
                    return [
                        "messageId": messageId,
                        "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
                        "error": "Command not supported"
                    ]
                }
            default:
                // Fire a pixel to report an application we want to support
                print("Unknown application")
            }
        }

        return nil
    }

    func handleConnection(using port: WKWebExtension.MessagePort, for extensionContext: WKWebExtensionContext) throws {
        port.disconnectHandler = { [weak self] error in
            if let error {
                Logger.webExtensions.log(("Message port disconnected: \(error)"))
            }
            self?.cancelConnection(with: port)
        }

        port.messageHandler = { [weak self] (message, error) in
            if let error {
                Logger.webExtensions.log(("Message handler error: \(error)"))
            }

            guard let message = message as? [String: Any] else {
                assertionFailure("Unknown type of message")
                return
            }

            Logger.webExtensions.log(("Received message from web extension: \(message)"))

            guard let connection = self?.connection(for: port) else {
                assertionFailure("Connection not found")
                return
            }

            let jsonData: Data
            do {
                jsonData = try JSONSerialization.data(withJSONObject: message, options: [])
            } catch {
                assertionFailure("Encoding error")
                Logger.webExtensions.log(("Failed to encode the message: \(message)"))
                jsonData = Data()
            }

            connection.communicator.send(messageData: jsonData)
        }

        guard let applicationIdentifier = port.applicationIdentifier else {
            throw NSError(domain: "com.duckduckgo.duckbrowser.nativemessaging", code: 1, userInfo: nil)
        }

        let path: String? = getExecutablePath(for: applicationIdentifier)

        guard let path else {
            throw NSError(domain: "com.duckduckgo.duckbrowser.nativemessaging", code: 2, userInfo: nil)
        }

        // Setup Bitwarden main app
        setupBitwardenApp()

        // Create the communicator for desktop_proxy
        let communicator = NativeMessagingCommunicator(appPath: path, arguments: [""])
        communicator.delegate = self
        let connection = NativeMessagingConnection(port: port, communicator: communicator)
        nativeMessagingConnections.append(connection)
    }

    private func getExecutablePath(for applicationIdentifier: String) -> String? {
        if applicationIdentifier == "com.8bit.bitwarden" {
            return "file:///Applications/Bitwarden.app/Contents/MacOS/desktop_proxy"
        }
        return nil
    }

    private func setupBitwardenApp() {
        let communicator1 = NativeMessagingCommunicator(appPath: "/Applications/Bitwarden.app/Contents/MacOS/Bitwarden", arguments: [""])
        do {
            try communicator1.runProxyProcess()
        } catch {
            print("Failed to setup Bitwarden app")
        }
        comm1 = communicator1
    }
}

// MARK: - NativeMessagingCommunicatorDelegate
@available(macOS 15.4, *)
@MainActor
extension BitwardenNativeMessagingHandler: @preconcurrency NativeMessagingCommunicatorDelegate {
    func nativeMessagingCommunicator(_ nativeMessagingCommunicator: any NativeMessagingCommunication, didReceiveMessageData messageData: Data) {

        guard let nativeMessagingCommunicator = nativeMessagingCommunicator as? NativeMessagingCommunicator else {
            assertionFailure("Unknown type of native messaging communicator")
            return
        }

        handleReceivedMessageData(messageData, communicator: nativeMessagingCommunicator)
    }

    private func handleReceivedMessageData(_ messageData: Data, communicator: NativeMessagingCommunicator) {
        guard let connection = connection(for: communicator) else {
            assertionFailure("Connection not found")
            return
        }

        do {
            let decodedMessage = try JSONDecoder().decode(String.self, from: messageData)
            Logger.webExtensions.log("Message received: \(decodedMessage)")
            connection.port.sendMessage(decodedMessage)
        } catch {
            assertionFailure("Failed to decode message")
            Logger.webExtensions.log(("Failed to decode the message: \(String(data: messageData, encoding: .utf8) ?? "")"))
        }
    }

    func nativeMessagingCommunicatorProcessDidTerminate(_ nativeMessagingCommunicator: any NativeMessagingCommunication) {
        Logger.webExtensions.log(("Process for native messaging terminated"))

        guard let nativeMessagingCommunicator = nativeMessagingCommunicator as? NativeMessagingCommunicator else {
            assertionFailure("Unknown type of native messaging communicator")
            return
        }

        // cancelConnection(with: nativeMessagingCommunicator)
    }
}

// MARK: - NativeMessagingConnectionDelegate
@available(macOS 15.4, *)
@MainActor
extension BitwardenNativeMessagingHandler: @preconcurrency NativeMessagingConnectionDelegate {

    func nativeMessagingConnectionProcessDidFail(_ nativeMessagingConnection: NativeMessagingConnection) {
        // cancelConnection(nativeMessagingConnection)
    }
}

// MARK: - Biometrics Methods
@available(macOS 15.4, *)
extension BitwardenNativeMessagingHandler {

    enum BiometricsStatus: Int {
        case available = 0
        case unlockNeeded = 1
        case hardwareUnavailable = 2
        case autoSetupNeeded = 3
        case manualSetupNeeded = 4
        case platformUnsupported = 5
        case desktopDisconnected = 6
        case notEnabledLocally = 7
        case notEnabledInConnectedDesktopApp = 8
    }

    private func getBiometricsStatusForUser(extensionContext: WKWebExtensionContext, messageId: Int) -> [String: Any] {
        return [
            "command": getBiometricsStatusForUser,
            "messageId": messageId,
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
            "response": BiometricsStatus.hardwareUnavailable.rawValue
        ]
        /*
        let laContext = LAContext()
        var error: NSError?

        // Check if biometric authentication is available on the device
        let canUseBiometrics = laContext.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            error: &error
        )

        // Basic implementation - can be expanded based on requirements
        if canUseBiometrics {
            return [
                "command": getBiometricsStatusForUser,
                "messageId": messageId,
                "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
                "response": BiometricsStatus.Available.rawValue
            ]
        } else {
            // Determine specific error status based on LocalAuthentication error
            let statusCode: Int
            if let authError = error as? LAError {
                switch authError.code {
                case .biometryNotAvailable:
                    statusCode = 2 // HardwareUnavailable
                case .biometryNotEnrolled:
                    statusCode = 3 // AutoSetupNeeded
                case .biometryLockout:
                    statusCode = 1 // UnlockNeeded
                default:
                    statusCode = 2 // HardwareUnavailable
                }
            } else {
                statusCode = 2 // HardwareUnavailable
            }

            return [
                "messageId": messageId,
                "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
                "response": statusCode
            ]
        }
        */
    }

    private func unlockWithBiometricsForUser(userId: String, messageId: Int) -> [String: Any] {
        print("[BitwardenNativeMessaging] Attempting biometric unlock for user: \(userId)")

        let context = LAContext()
        context.interactionNotAllowed = false

        // Try to read the biometric-protected keychain item
        // This will trigger the macOS keychain dialog
        let keychainAccount = "\(userId)_user_biometric"
        print("[BitwardenNativeMessaging] Looking for keychain account: \(keychainAccount)")
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Bitwarden_biometric",
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecUseAuthenticationContext as String: context
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            if let data = result as? Data {
                print("[BitwardenNativeMessaging] Successfully retrieved vault key via biometrics")
                // Return the actual keychain data as base64
                let userKeyB64 = data.base64EncodedString()

                return [
                    "messageId": messageId,
                    "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
                    "response": true,
                    "userKeyB64": userKeyB64
                ]
            } else {
                print("[BitwardenNativeMessaging] Retrieved keychain data but couldn't decode")
                return [
                    "messageId": messageId,
                    "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
                ]
            }
        case errSecUserCanceled: // errSecUserCancel
            print("[BitwardenNativeMessaging] User cancelled biometric authentication")
            return [
                "messageId": messageId,
                "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
            ]
        case -25293: // errSecAuthFailed  
            print("[BitwardenNativeMessaging] Biometric authentication failed")
            return [
                "messageId": messageId,
                "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
            ]
        case -25300: // errSecItemNotFound
            print("[BitwardenNativeMessaging] Keychain item not found")
            return [
                "messageId": messageId,
                "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
            ]
        case -25308: // errSecInteractionNotAllowed
            print("[BitwardenNativeMessaging] Keychain interaction not allowed - missing permissions")
            return [
                "messageId": messageId,
                "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
            ]
        default:
            print("[BitwardenNativeMessaging] Keychain access failed with status: \(status)")
            print("[BitwardenNativeMessaging] Error description: \(SecCopyErrorMessageString(OSStatus(status), nil) ?? "Unknown error" as CFString)")
            return [
                "messageId": messageId,
                "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
            ]
        }
    }
}

#endif
