//
//  OnePasswordNativeMessagingHandler.swift
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

@available(macOS 15.4, *)
final class OnePasswordNativeMessagingHandler: NativeMessagingHandling {

    // MARK: - NativeMessagingHandling

    func handleMessage(_ message: Any, to applicationIdentifier: String?, for extensionContext: WKWebExtensionContext) throws -> Any? {
        Logger.webExtensions.log("1Password native messaging handler received message - not implemented")

        guard let message = message as? [String: Any] else {
            return ["error": "1Password native messaging not implemented"]
        }

        switch message["name"] as? String {
        case "request-os-version":
            return ["result": "15.6.1"]
        default:
            return ["error": "1Password native messaging not implemented"]
        }
    }

    func handleConnection(using port: WKWebExtension.MessagePort, for extensionContext: WKWebExtensionContext) throws {
        // Connection handling currently disabled
        /*
        Logger.webExtensions.log("1Password native messaging handler connection - not implemented")
        
        port.disconnectHandler = { error in
            if let error {
                Logger.webExtensions.log("1Password message port disconnected: \(error)")
            }
            // Placeholder - no connection cleanup needed
        }
        
        // Placeholder - no actual connection setup
        */
    }

}

#endif
