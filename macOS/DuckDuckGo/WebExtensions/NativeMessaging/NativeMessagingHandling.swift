//
//  NativeMessagingHandling.swift
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
import WebKit

@available(macOS 15.4, *)
protocol NativeMessagingHandling {
    var nativeMessagingConnections: [NativeMessagingConnection] { get set }

    func handleMessage(_ message: Any, to applicationIdentifier: String?, for extensionContext: WKWebExtensionContext) throws -> Any?
    func handleConnection(using port: WKWebExtension.MessagePort, for extensionContext: WKWebExtensionContext) throws
}

@available(macOS 15.4, *)
extension NativeMessagingHandling {

    // Default implementations of common functionality
    func connection(for port: WKWebExtension.MessagePort) -> NativeMessagingConnection? {
        return nativeMessagingConnections.first(where: { $0.port === port })
    }

    func connection(for communicator: NativeMessagingCommunicator) -> NativeMessagingConnection? {
        return nativeMessagingConnections.first(where: { communicator === $0.communicator })
    }

    mutating func cancelConnection(_ connection: NativeMessagingConnection) {
        nativeMessagingConnections.removeAll { $0 === connection }
    }

    mutating func cancelConnection(with port: WKWebExtension.MessagePort) {
        nativeMessagingConnections.removeAll { $0.port === port }
    }

    mutating func cancelConnection(with communicator: NativeMessagingCommunicator) {
        nativeMessagingConnections.removeAll { $0.communicator === communicator }
    }
}

#endif
