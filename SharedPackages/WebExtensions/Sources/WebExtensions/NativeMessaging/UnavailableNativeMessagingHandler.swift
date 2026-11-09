//
//  UnavailableNativeMessagingHandler.swift
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

import os.log
import WebKit

/// Refuses native messaging where the app can't start another app's host, such as in the App Store
/// sandbox, and records each extension that tries, so the app can tell the user why the extension
/// can't reach its desktop app.
///
/// The extension sees what it would see without a host: the port disconnects and the message fails.
@available(macOS 15.4, iOS 18.4, *)
@MainActor
public final class UnavailableNativeMessagingHandler: WebExtensionNativeMessagingHandling {
    private let noticeStore: NativeMessagingNoticeStoring

    public init(noticeStore: NativeMessagingNoticeStoring) {
        self.noticeStore = noticeStore
    }

    public func connect(
        _ port: WKWebExtension.MessagePort,
        applicationIdentifier: String?,
        for context: WKWebExtensionContext
    ) async throws {
        recordAttempt(to: applicationIdentifier, from: context)
        throw WKWebExtension.MessagePort.Error(.notConnected)
    }

    public func hasOpenPorts(for context: WKWebExtensionContext) -> Bool {
        false
    }

    public func sendMessage(
        _ message: Any,
        applicationIdentifier: String?,
        for context: WKWebExtensionContext
    ) async throws -> Any? {
        recordAttempt(to: applicationIdentifier, from: context)
        throw WKWebExtension.MessagePort.Error(.notConnected)
    }

    private func recordAttempt(to applicationIdentifier: String?, from context: WKWebExtensionContext) {
        let isFirstAttempt = noticeStore.recordAttempt(for: context.uniqueIdentifier)
        let displayName = context.webExtension.displayName ?? "(unknown)"
        Logger.webExtensions.info("Native messaging is unavailable: \(displayName) tried \(applicationIdentifier ?? "(none)", privacy: .public), first attempt: \(isFirstAttempt)")
    }
}
