//
//  WebExtensionPermissionController.swift
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

import Combine
import os.log
import WebKit

@available(macOS 15.4, iOS 18.4, *)
public struct WebExtensionPermissionRequest {
    public let permissions: Set<WKWebExtension.Permission>
    public let matchPatterns: Set<WKWebExtension.MatchPattern>
    public let urls: Set<URL>

    public init(permissions: Set<WKWebExtension.Permission> = [],
                matchPatterns: Set<WKWebExtension.MatchPattern> = [],
                urls: Set<URL> = []) {
        self.permissions = permissions
        self.matchPatterns = matchPatterns
        self.urls = urls
    }
}

@available(macOS 15.4, iOS 18.4, *)
@MainActor
public protocol WebExtensionPermissionPrompting {
    /// Used to handle granting permissions for an extension upon installation
    func confirmInstallation(of webExtension: WKWebExtension, permissions: WebExtensionPermissionRequest) async -> WebExtensionPermissionInstallationPromptResult

    /// Used to handle granting permissions for an extension at runtime
    func confirmPermissions(_ permissions: WebExtensionPermissionRequest, for context: WKWebExtensionContext) async -> WebExtensionPermissionPromptResult
}

@available(macOS 15.4, iOS 18.4, *)
@MainActor
public enum WebExtensionPermissionInstallationPromptResult: Equatable {
    case granted(privateDataAccess: Bool)
    case denied
}

@available(macOS 15.4, iOS 18.4, *)
@MainActor
public enum WebExtensionPermissionPromptResult: Equatable {
    case granted
    case denied
}

@available(macOS 15.4, iOS 18.4, *)
@MainActor
public final class WebExtensionPermissionController {
    public enum PermissionError: Error {
        case installationDenied
    }

    private let store: any WebExtensionPermissionStoring
    private let installationStore: any InstalledWebExtensionStoring
    private let prompter: any WebExtensionPermissionPrompting
    private var observations: [String: Set<AnyCancellable>] = [:]
    private var contexts: [String: WKWebExtensionContext] = [:]
    // Trust comes from the browser's install path, never from a user-supplied manifest.
    var trustedInstallations: Set<String> = []

    public init(store: any WebExtensionPermissionStoring,
                installationStore: any InstalledWebExtensionStoring,
                prompter: any WebExtensionPermissionPrompting) {
        self.store = store
        self.installationStore = installationStore
        self.prompter = prompter
    }

    func isTrusted(_ identifier: String) -> Bool {
        trustedInstallations.contains(identifier) || installationStore.installedExtension(withUniqueIdentifier: identifier)?.isEmbedded == true
    }

    func prepare(_ context: WKWebExtensionContext) async throws {
        let identifier = context.uniqueIdentifier
        if isTrusted(identifier) {
            for permission in context.webExtension.requestedPermissions {
                context.setPermissionStatus(.grantedExplicitly, for: permission)
            }
            for pattern in context.webExtension.allRequestedMatchPatterns {
                context.setPermissionStatus(.grantedExplicitly, for: pattern)
            }
            context.hasAccessToPrivateData = true
            return
        }

        observations.removeValue(forKey: identifier)
        contexts[identifier] = context
        do {
            if let settings = try store.settings(for: identifier) {
                try restore(settings, to: context)
            } else {
                let request = WebExtensionPermissionRequest(permissions: context.webExtension.requestedPermissions,
                                                            matchPatterns: context.webExtension.allRequestedMatchPatterns)
                let result = await prompter.confirmInstallation(of: context.webExtension, permissions: request)
                guard case .granted(let privateDataAccess) = result, contexts[identifier] === context else {
                    throw PermissionError.installationDenied
                }
                context.hasAccessToPrivateData = privateDataAccess
                grant(request, to: context)
                try save(context)
            }
            observePermissionChanges(in: context)
        } catch {
            if contexts[identifier] === context {
                contexts.removeValue(forKey: identifier)
            }
            throw error
        }
    }

    func request(_ request: WebExtensionPermissionRequest, for context: WKWebExtensionContext) async -> Bool {
        if isTrusted(context.uniqueIdentifier) { return true }
        guard contexts[context.uniqueIdentifier] === context,
              await prompter.confirmPermissions(request, for: context) == .granted,
              contexts[context.uniqueIdentifier] === context else { return false }

        let previousPermissions = context.grantedPermissions
        let previousPatterns = context.grantedPermissionMatchPatterns
        do {
            grant(request, to: context)
            try save(context)
            return true
        } catch {
            context.grantedPermissions = previousPermissions
            context.grantedPermissionMatchPatterns = previousPatterns
            Logger.webExtensions.error("Could not save extension permissions: \(error.localizedDescription)")
            return false
        }
    }

    /// Also updates a loaded context, so a future preferences UI can use the same entry point.
    public func setHasAccessToPrivateData(_ allowed: Bool, for identifier: String) throws {
        guard var settings = try store.settings(for: identifier) else { return }
        settings.hasAccessToPrivateData = allowed
        try store.save(settings, for: identifier)
        contexts[identifier]?.hasAccessToPrivateData = allowed
        NotificationCenter.default.post(name: .webExtensionPrivateAccessDidChange, object: self)
    }

    func forget(_ identifier: String) throws {
        try store.removeSettings(for: identifier)
        observations.removeValue(forKey: identifier)
        contexts.removeValue(forKey: identifier)
    }

    func didUnload(_ identifier: String) {
        // Invalidate pending prompts without forgetting consent on reload or data clearing.
        if let context = contexts[identifier] {
            do {
                try save(context)
            } catch {
                Logger.webExtensions.error("Could not save extension permissions before unloading: \(error.localizedDescription)")
            }
        }
        observations.removeValue(forKey: identifier)
        contexts.removeValue(forKey: identifier)
    }

    private func restore(_ settings: WebExtensionPermissionSettings, to context: WKWebExtensionContext) throws {
        context.hasAccessToPrivateData = settings.hasAccessToPrivateData
        context.grantedPermissions = Dictionary(uniqueKeysWithValues: settings.grantedPermissions.map {
            (WKWebExtension.Permission($0.key), $0.value)
        })
        context.grantedPermissionMatchPatterns = try Dictionary(uniqueKeysWithValues: settings.grantedMatchPatterns.map {
            (try WKWebExtension.MatchPattern(string: $0.key), $0.value)
        })
        context.hasRequestedOptionalAccessToAllHosts = settings.hasRequestedOptionalAccessToAllHosts
    }

    private func grant(_ request: WebExtensionPermissionRequest, to context: WKWebExtensionContext) {
        for permission in request.permissions {
            context.setPermissionStatus(.grantedExplicitly, for: permission)
        }
        for pattern in request.matchPatterns {
            context.setPermissionStatus(.grantedExplicitly, for: pattern)
        }
        for url in request.urls {
            context.setPermissionStatus(.grantedExplicitly, for: url)
        }
    }

    private func save(_ context: WKWebExtensionContext) throws {
        guard contexts[context.uniqueIdentifier] === context else { return }
        var settings = WebExtensionPermissionSettings()
        settings.hasAccessToPrivateData = context.hasAccessToPrivateData
        settings.grantedPermissions = Dictionary(uniqueKeysWithValues: context.grantedPermissions.map { ($0.key.rawValue, $0.value) })
        settings.grantedMatchPatterns = Dictionary(uniqueKeysWithValues: context.grantedPermissionMatchPatterns.map { ($0.key.string, $0.value) })
        settings.hasRequestedOptionalAccessToAllHosts = context.hasRequestedOptionalAccessToAllHosts
        try store.save(settings, for: context.uniqueIdentifier)
        Logger.webExtensions.debug("Saved permissions to store for \(context.uniqueIdentifier)")
    }

    private func observePermissionChanges(in context: WKWebExtensionContext) {
        // Includes permissions.remove(), so revoked optional grants cannot return on relaunch.
        let notifications = [WKWebExtensionContext.permissionsWereGrantedNotification,
                             WKWebExtensionContext.grantedPermissionsWereRemovedNotification,
                             WKWebExtensionContext.permissionMatchPatternsWereGrantedNotification,
                             WKWebExtensionContext.grantedPermissionMatchPatternsWereRemovedNotification]
        observations[context.uniqueIdentifier] = Set(notifications.map { name in
            NotificationCenter.default.publisher(for: name, object: context).sink { [weak self, weak context] notification in
                MainActor.assumeIsolated {
                    guard let self, let context else { return }
                    do {
                        Logger.webExtensions.debug("Notification received: \(notification.name.rawValue) for \(context.uniqueIdentifier)")
                        try self.save(context)
                    } catch {
                        Logger.webExtensions.error("Could not save changed extension permissions: \(error.localizedDescription)")
                    }
                }
            }
        })
    }
}

public extension Notification.Name {
    static let webExtensionPrivateAccessDidChange = Notification.Name("webExtensionPrivateAccessDidChange")
}
