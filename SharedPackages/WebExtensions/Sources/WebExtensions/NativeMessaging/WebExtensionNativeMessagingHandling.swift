//
//  WebExtensionNativeMessagingHandling.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

import WebKit

/// Talks to a native messaging host on behalf of an extension.
///
/// An extension reaches a companion app through `runtime.sendNativeMessage` for one message,
/// or through `runtime.connectNative` for a port that stays open. Bitwarden needs the port:
/// its biometric unlock waits for an answer from `com.8bit.bitwarden`.
///
/// Only macOS implements this. A host is a separate executable, and iOS has no such process.
@available(macOS 15.4, iOS 18.4, *)
@MainActor
public protocol WebExtensionNativeMessagingHandling: AnyObject {

    /// Connects a port that stays open to the named host.
    ///
    /// The implementation owns the port until either side disconnects.
    func connect(_ port: WKWebExtension.MessagePort,
                 applicationIdentifier: String?,
                 for context: WKWebExtensionContext) async throws

    /// Sends one message to the named host and returns its answer.
    func sendMessage(_ message: Any,
                     applicationIdentifier: String?,
                     for context: WKWebExtensionContext) async throws -> Any?
}
