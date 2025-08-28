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
    private var bitwardenHandler = BitwardenNativeMessagingHandler()

    private func connection(for port: WKWebExtension.MessagePort) -> NativeMessagingConnection? {
        return bitwardenHandler.connection(for: port)
    }

    private func connection(for communicator: NativeMessagingCommunicator) -> NativeMessagingConnection? {
        return bitwardenHandler.connection(for: communicator)
    }

    private func cancelConnection(_ connection: NativeMessagingConnection) {
        bitwardenHandler.cancelConnection(connection)
        // Sync back to coordinator's connections
        nativeMessagingConnections = bitwardenHandler.nativeMessagingConnections
    }

    private func cancelConnection(with port: WKWebExtension.MessagePort) {
        bitwardenHandler.cancelConnection(with: port)
        // Sync back to coordinator's connections
        nativeMessagingConnections = bitwardenHandler.nativeMessagingConnections
    }

    private func cancelConnection(with communicator: NativeMessagingCommunicator) {
        bitwardenHandler.cancelConnection(with: communicator)
        // Sync back to coordinator's connections
        nativeMessagingConnections = bitwardenHandler.nativeMessagingConnections
    }

    func webExtensionController(_ controller: WKWebExtensionController, sendMessage message: Any, to applicationIdentifier: String?, for extensionContext: WKWebExtensionContext) async throws -> Any? {
        // For now, assume Bitwarden relationship and delegate directly to the handler
        return try bitwardenHandler.handleMessage(message, to: applicationIdentifier, for: extensionContext)
    }
    func webExtensionController(_ controller: WKWebExtensionController, connectUsingMessagePort port: WKWebExtension.MessagePort, for extensionContext: WKWebExtensionContext) throws {
        // For now, assume Bitwarden relationship and delegate directly to the handler
        try bitwardenHandler.handleConnection(using: port, for: extensionContext)

        // Sync the connections with the handler's connections
        nativeMessagingConnections = bitwardenHandler.nativeMessagingConnections
    }
}

@available(macOS 15.4, *)
@MainActor
extension NativeMessagingCoordinator: @preconcurrency NativeMessagingCommunicatorDelegate {
    func nativeMessagingCommunicator(_ nativeMessagingCommunicator: any NativeMessagingCommunication, didReceiveMessageData messageData: Data) {
        // Route to the handler since it manages the connections
        bitwardenHandler.nativeMessagingCommunicator(nativeMessagingCommunicator, didReceiveMessageData: messageData)
        // Sync connections back
        nativeMessagingConnections = bitwardenHandler.nativeMessagingConnections
    }

    func nativeMessagingCommunicatorProcessDidTerminate(_ nativeMessagingCommunicator: any NativeMessagingCommunication) {
        // Route to the handler since it manages the connections  
        bitwardenHandler.nativeMessagingCommunicatorProcessDidTerminate(nativeMessagingCommunicator)
        // Sync connections back
        nativeMessagingConnections = bitwardenHandler.nativeMessagingConnections
    }
}

@available(macOS 15.4, *)
@MainActor
extension NativeMessagingCoordinator: @preconcurrency NativeMessagingConnectionDelegate {

    func nativeMessagingConnectionProcessDidFail(_ nativeMessagingConnection: NativeMessagingConnection) {
        // Route to the handler since it manages the connections
        bitwardenHandler.nativeMessagingConnectionProcessDidFail(nativeMessagingConnection)
        // Sync connections back
        nativeMessagingConnections = bitwardenHandler.nativeMessagingConnections
    }

}

#endif
