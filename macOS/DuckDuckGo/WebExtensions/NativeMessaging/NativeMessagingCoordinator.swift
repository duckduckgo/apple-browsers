//
//  NativeMessagingCoordinator.swift
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
final class NativeMessagingCoordinator {

    var nativeMessagingConnections = [NativeMessagingConnection]()

    private func connection(for port: WKWebExtension.MessagePort) -> NativeMessagingConnection? {
        return nativeMessagingConnections.first(where: { $0.port === port })
    }

    private func connection(for communicator: NativeMessagingCommunicator) -> NativeMessagingConnection? {
        return nativeMessagingConnections.first(where: { communicator === $0.communicator })
    }

    private func cancelConnection(_ connection: NativeMessagingConnection) {
        nativeMessagingConnections.removeAll { $0 === connection }
    }

    private func cancelConnection(with port: WKWebExtension.MessagePort) {
        nativeMessagingConnections.removeAll { $0.port === port }
    }

    private func cancelConnection(with communicator: NativeMessagingCommunicator) {
        nativeMessagingConnections.removeAll { $0.communicator === communicator }
    }

    func webExtensionController(_ controller: WKWebExtensionController, sendMessage message: Any, to applicationIdentifier: String?, for extensionContext: WKWebExtensionContext) async throws -> Any? {

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
                    return [
                        "command": "authenticateWithBiometrics",
                        "response": false,
                        "timestamp": Int64(NSDate().timeIntervalSince1970 * 1000),
                        "messageId": messageId,
                    ]
                case "biometricUnlock":
                    return [
                        "command": "authenticateWithBiometrics",
                        "response": "not supported",
                        "timestamp": Int64(NSDate().timeIntervalSince1970 * 1000),
                        "messageId": messageId,
                    ]
                case "biometricUnlockAvailable":
                    return [
                        "command": "authenticateWithBiometrics",
                        "response": "not available",
                        "timestamp": Int64(NSDate().timeIntervalSince1970 * 1000),
                        "messageId": messageId,
                    ]
                case "getBiometricsStatus":
                    return [
                        "command": "getBiometricsStatus",
                        "messageId": messageId,
                        "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
                        "response": BiometricsStatus.available.rawValue
                    ]
                case "getBiometricsStatusForUser":
                    return [
                        "command": "getBiometricsStatusForUser",
                        "messageId": messageId,
                        "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
                        "response": BiometricsStatus.available.rawValue
                    ]
                case "unlockWithBiometricsForUser":
                    return [
                        "command": "unlockWithBiometricsForUser",
                        "response": false,
                        "timestamp": Int64(NSDate().timeIntervalSince1970 * 1000),
                        "messageId": messageId,
                    ]
                case "sleep":
                    // The Bitwarden extension returns no message here
                    return nil
                default:
                    print("[NativeMessaging] Unhandled command: \(command)")
                    return nil
                }
            default:
                // Fire a pixel to report an application we want to support
                print("Unknown application")
            }
        }

        return nil
    }
/*
    func webExtensionController(_ controller: WKWebExtensionController, connectUsingMessagePort port: WKWebExtension.MessagePort, for extensionContext: WKWebExtensionContext) throws {
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
        comm1 = communicator1

        // Create the communicator (either immediately if app was running, or this is for other apps)
        let communicator = NativeMessagingCommunicator(appPath: path, arguments: [""])
        communicator.delegate = self
        let connection = NativeMessagingConnection(port: port,
                                                   communicator: communicator)
        nativeMessagingConnections.append(connection)
    }
 */
}

@available(macOS 15.4, *)
@MainActor
extension NativeMessagingCoordinator: @preconcurrency NativeMessagingCommunicatorDelegate {
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

        cancelConnection(with: nativeMessagingCommunicator)
    }
}

@available(macOS 15.4, *)
extension NativeMessagingCoordinator {
    // MARK: - Biometrics Status

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

}

@available(macOS 15.4, *)
@MainActor
extension NativeMessagingCoordinator: @preconcurrency NativeMessagingConnectionDelegate {

    func nativeMessagingConnectionProcessDidFail(_ nativeMessagingConnection: NativeMessagingConnection) {
        cancelConnection(nativeMessagingConnection)
    }

}

#endif
