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

import Foundation
import os.log
import WebKit
import LocalAuthentication

@available(macOS 15.4, *)
final class BitwardenNativeMessagingHandler: NativeMessagingHandling {

    private static let ServiceNameBiometric = "Bitwarden_biometric"

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

    func handleMessage(_ message: Any, to applicationIdentifier: String?, for extensionContext: WKWebExtensionContext) async throws -> Any? {

        if let message = message as? [String: Any] {
            switch applicationIdentifier {
            case "com.bitwarden.desktop", "com.8bit.bitwarden":
                guard let command = message["command"] as? String else {
                    throw NSError(domain: "NativeMessagingCoordinator", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing 'command' field in the message"])
                }

                // Extract messageId for response
                let messageId = message["messageId"] as? Int ?? 0

                switch command {
                case "downloadFile":
                    // Probably need this... will test
                    return nil
                case "copyToClipboard":
                    guard let string = message["data"] as? String else {
                        throw NSError(domain: "NativeMessagingCoordinator", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing 'data' field in the message"])
                    }

                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(string, forType: .string)
                    return [
                        "command": command,
                        "messageId": messageId,
                        "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
                        "success": true
                    ]
                case "readFromClipboard":
                    // We have purposedly not implemented this as it's unclear why we'd give the extension free access to the clipboard.
                    // The user can still paste normally, which is handled by the native app.
                    return nil
                case "showPopover":
                    // We have purposedly not implemented this as it's unclear why we'd give the extension free access to the clipboard.
                    // The user can still paste normally, which is handled by the native app.
                    return nil
                case "authenticateWithBiometrics":
                    return await self.handleAuthenticateWithBiometrics(messageId: messageId)
                case "getBiometricsStatus":
                    return [
                        "command": "getBiometricsStatus",
                        "response": BiometricsStatus.available.rawValue,
                        "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
                        "messageId": messageId
                    ]
                case "unlockWithBiometricsForUser":
                    guard let userId = message["userId"] as? String else {
                        throw NSError(domain: "NativeMessagingCoordinator", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing 'userId' field in the message"])
                    }
                    return await self.handleUnlockWithBiometricsForUser(messageId: messageId, userId: userId)
                case "getBiometricsStatusForUser":
                    guard let userId = message["userId"] as? String else {
                        throw NSError(domain: "NativeMessagingCoordinator", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing 'userId' field in the message"])
                    }
                    return self.handleGetBiometricsStatusForUser(messageId: messageId, userId: userId)
                case "biometricUnlock":
                    guard let userId = message["userId"] as? String else {
                        throw NSError(domain: "NativeMessagingCoordinator", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing 'userId' field in the message"])
                    }
                    return await self.handleBiometricUnlock(userId: userId)
                case "biometricUnlockAvailable":
                    return self.handleBiometricUnlockAvailable()
                case "sleep":
                    // This is for the app to lock the vault after a while - we do nothing here since we don't control the vault
                    return nil
                default:
                    Logger.webExtensions.info("[NativeMessaging] Unhandled command: \(command, privacy: .private)")
                    return nil
                }
            default:
                Logger.webExtensions.fault("Bitwarden native messaging called for unknown application: \(applicationIdentifier ?? "nil")")
            }
        }

        return nil
    }

    func handleConnection(using port: WKWebExtension.MessagePort, for extensionContext: WKWebExtensionContext) throws {
        // Persistent connections currently disabled
        /*
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

        let path: String? = {
            if applicationIdentifier == "com.8bit.bitwarden" {
                // return "file:///Applications/Bitwarden.app/Contents/MacOS/Bitwarden"
                return "file:///Applications/Bitwarden.app/Contents/MacOS/desktop_proxy"
            }

            return nil
        }()

        guard let path else {
            throw NSError(domain: "com.duckduckgo.duckbrowser.nativemessaging", code: 2, userInfo: nil)
        }

        let communicator1 = NativeMessagingCommunicator(appPath: "/Applications/Bitwarden.app/Contents/MacOS/Bitwarden", arguments: [""])
        do {
            try communicator1.runProxyProcess()
        } catch {
            print("asd")
        }

        // Create the communicator (either immediately if app was running, or this is for other apps)
        let communicator = NativeMessagingCommunicator(appPath: path, arguments: [""])
        communicator.delegate = self
        let connection = NativeMessagingConnection(port: port,
                                                   communicator: communicator)
        nativeMessagingConnections.append(connection)
        */
    }

    // MARK: - Biometrics Helper Methods

    private func handleAuthenticateWithBiometrics(messageId: Int) async -> [String: Any] {
        let laContext = LAContext()
        guard let accessControl = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, [.privateKeyUsage, .userPresence], nil) else {
            return [
                "command": "authenticateWithBiometrics",
                "response": false,
                "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
                "messageId": messageId
            ]
        }

        do {
            let success = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
                laContext.evaluateAccessControl(accessControl, operation: .useKeySign, localizedReason: "authenticate") { success, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: success)
                    }
                }
            }

            return [
                "command": "authenticateWithBiometrics",
                "response": success,
                "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
                "messageId": messageId
            ]
        } catch {
            return [
                "command": "authenticateWithBiometrics",
                "response": false,
                "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
                "messageId": messageId
            ]
        }
    }

    private func handleUnlockWithBiometricsForUser(messageId: Int, userId: String) async -> [String: Any] {
        var error: NSError?
        let laContext = LAContext()

        laContext.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)

        if let e = error, e.code != kLAErrorBiometryLockout {
            return [
                "command": "unlockWithBiometricsForUser",
                "response": false,
                "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
                "messageId": messageId
            ]
        }

        var flags: SecAccessControlCreateFlags = [.privateKeyUsage]
        // https://developer.apple.com/documentation/security/secaccesscontrolcreateflags/biometryany
        if #available(macOS 10.13.4, *) {
            flags.insert(.biometryAny)
        } else {
            flags.insert(.touchIDAny)
        }

        guard let accessControl = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, flags, nil) else {
            return [
                "command": "unlockWithBiometricsForUser",
                "response": false,
                "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
                "messageId": messageId
            ]
        }

        do {
            let success = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
                laContext.evaluateAccessControl(accessControl, operation: .useKeySign, localizedReason: "unlock your vault") { success, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: success)
                    }
                }
            }

            if success {
                let passwordName = userId + "_user_biometric"
                var passwordLength: UInt32 = 0
                var passwordPtr: UnsafeMutableRawPointer?

                var status = SecKeychainFindGenericPassword(nil, UInt32(Self.ServiceNameBiometric.utf8.count), Self.ServiceNameBiometric, UInt32(passwordName.utf8.count), passwordName, &passwordLength, &passwordPtr, nil)
                if status != errSecSuccess {
                    let fallbackName = "key"
                    status = SecKeychainFindGenericPassword(nil, UInt32(Self.ServiceNameBiometric.utf8.count), Self.ServiceNameBiometric, UInt32(fallbackName.utf8.count), fallbackName, &passwordLength, &passwordPtr, nil)
                }

                if status == errSecSuccess, let passwordPtr = passwordPtr {
                    let result = NSString(bytes: passwordPtr, length: Int(passwordLength), encoding: String.Encoding.utf8.rawValue) as String?
                    SecKeychainItemFreeContent(nil, passwordPtr)

                    return [
                        "command": "unlockWithBiometricsForUser",
                        "response": true,
                        "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
                        "userKeyB64": result?.replacingOccurrences(of: "\"", with: "") ?? "",
                        "messageId": messageId
                    ]
                } else {
                    return [
                        "command": "unlockWithBiometricsForUser",
                        "response": true,
                        "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
                        "messageId": messageId
                    ]
                }
            } else {
                return [
                    "command": "unlockWithBiometricsForUser",
                    "response": false,
                    "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
                    "messageId": messageId
                ]
            }
        } catch {
            return [
                "command": "unlockWithBiometricsForUser",
                "response": false,
                "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
                "messageId": messageId
            ]
        }
    }

    private func handleGetBiometricsStatusForUser(messageId: Int, userId: String) -> [String: Any] {
        let laContext = LAContext()
        if !laContext.isBiometricsAvailable() {
            return [
                "command": "getBiometricsStatusForUser",
                "response": BiometricsStatus.hardwareUnavailable.rawValue,
                "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
                "messageId": messageId
            ]
        }

        let passwordName = userId + "_user_biometric"

        // TEMPORARY: Use SecItemCopyMatching to request keychain access - remove this later
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.ServiceNameBiometric,
            kSecAttrAccount as String: passwordName,
            kSecReturnData as String: true
        ]

        var status = SecItemCopyMatching(query as CFDictionary, nil)
        if status != errSecSuccess {
            let fallbackQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: Self.ServiceNameBiometric,
                kSecAttrAccount as String: "key",
                kSecReturnData as String: true
            ]
            status = SecItemCopyMatching(fallbackQuery as CFDictionary, nil)
        }

        if status == errSecSuccess {
            return [
                "command": "getBiometricsStatusForUser",
                "response": BiometricsStatus.available.rawValue,
                "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
                "messageId": messageId
            ]
        } else {
            return [
                "command": "getBiometricsStatusForUser",
                "response": BiometricsStatus.notEnabledInConnectedDesktopApp.rawValue,
                "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
                "messageId": messageId
            ]
        }
    }

    private func handleBiometricUnlock(userId: String) async -> [String: Any] {
        let laContext = LAContext()

        if !laContext.isBiometricsAvailable() {
            return [
                "command": "biometricUnlock",
                "response": "not supported",
                "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
            ]
        }

        guard let accessControl = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, [.privateKeyUsage, .userPresence], nil) else {
            return [
                "command": "biometricUnlock",
                "response": "not supported",
                "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
            ]
        }

        do {
            let success = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
                laContext.evaluateAccessControl(accessControl, operation: .useKeySign, localizedReason: "Biometric Unlock") { success, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: success)
                    }
                }
            }

            if success {
                let passwordName = userId + "_user_biometric"
                var passwordLength: UInt32 = 0
                var passwordPtr: UnsafeMutableRawPointer?

                var status = SecKeychainFindGenericPassword(nil, UInt32(Self.ServiceNameBiometric.utf8.count), Self.ServiceNameBiometric, UInt32(passwordName.utf8.count), passwordName, &passwordLength, &passwordPtr, nil)
                if status != errSecSuccess {
                    let fallbackName = "key"
                    status = SecKeychainFindGenericPassword(nil, UInt32(Self.ServiceNameBiometric.utf8.count), Self.ServiceNameBiometric, UInt32(fallbackName.utf8.count), fallbackName, &passwordLength, &passwordPtr, nil)
                }

                if status == errSecSuccess, let passwordPtr = passwordPtr {
                    let result = NSString(bytes: passwordPtr, length: Int(passwordLength), encoding: String.Encoding.utf8.rawValue) as String?
                    SecKeychainItemFreeContent(nil, passwordPtr)

                    return [
                        "command": "biometricUnlock",
                        "response": "unlocked",
                        "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
                        "userKeyB64": result?.replacingOccurrences(of: "\"", with: "") ?? ""
                    ]
                } else {
                    return [
                        "command": "biometricUnlock",
                        "response": "not enabled",
                        "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
                    ]
                }
            } else {
                return [
                    "command": "biometricUnlock",
                    "response": "not supported",
                    "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
                ]
            }
        } catch {
            return [
                "command": "biometricUnlock",
                "response": "not supported",
                "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
            ]
        }
    }

    private func handleBiometricUnlockAvailable() -> [String: Any] {
        let laContext = LAContext()
        let isAvailable = laContext.isBiometricsAvailable()

        return [
            "command": "biometricUnlockAvailable",
            "response": isAvailable ? "available" : "not available",
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
        ]
    }
}

// MARK: - LAContext Extension

extension LAContext {
    func isBiometricsAvailable() -> Bool {
        return canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }
}
