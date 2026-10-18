//
//  WebExtensionCommandShortcutStore.swift
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

#if os(macOS)
import AppKit
import os.log
import Persistence
import WebKit

/// A keyboard shortcut for an extension command: a key, such as `y`, and its modifiers.
/// A `nil` key means the command has no shortcut.
public struct WebExtensionCommandShortcut: Codable, Equatable {
    public let activationKey: String?
    public let modifierFlags: UInt

    public init(activationKey: String?, modifierFlags: NSEvent.ModifierFlags) {
        self.activationKey = activationKey
        self.modifierFlags = modifierFlags.rawValue
    }
}

/// The keyboard shortcuts the user picked for extension commands.
///
/// WebKit starts every command with the shortcut its manifest suggests, and leaves saving any change
/// to the app. The store saves the user's shortcuts per installation and command in the key-value store,
/// and applies them again each time an extension loads. Like extension permissions, an update copies them
/// to the replacement installation, and uninstalling removes them.
@available(macOS 15.4, *)
@MainActor
public final class WebExtensionCommandShortcutStore {

    private static let keyPrefix = "web-extension-command-shortcuts"

    private let keyValueStore: any ThrowingKeyValueStoring
    /// The manifest shortcut of each command, by extension and command, captured before the first
    /// change, so a command can go back to it.
    private var defaults: [String: [String: WebExtensionCommandShortcut]] = [:]

    nonisolated public init(keyValueStore: any ThrowingKeyValueStoring) {
        self.keyValueStore = keyValueStore
    }

    /// Applies the saved shortcuts to the commands of `contexts`.
    public func apply(to contexts: Set<WKWebExtensionContext>) {
        for context in contexts {
            captureDefaults(of: context)
            let saved = savedShortcuts(for: context.uniqueIdentifier)
            for command in context.commands {
                if let shortcut = saved[command.id] {
                    command.apply(shortcut)
                }
            }
        }
    }

    /// Whether the user changed the shortcut of `command`.
    public func isCustomized(_ command: WKWebExtension.Command, in context: WKWebExtensionContext) -> Bool {
        savedShortcuts(for: context.uniqueIdentifier)[command.id] != nil
    }

    /// Sets and saves the shortcut of `command`.
    public func setShortcut(_ shortcut: WebExtensionCommandShortcut, for command: WKWebExtension.Command, in context: WKWebExtensionContext) {
        captureDefaults(of: context)
        var saved = savedShortcuts(for: context.uniqueIdentifier)
        saved[command.id] = shortcut
        save(saved, for: context.uniqueIdentifier)
        command.apply(shortcut)
    }

    /// Puts back the manifest shortcut of `command`.
    public func resetShortcut(for command: WKWebExtension.Command, in context: WKWebExtensionContext) {
        var saved = savedShortcuts(for: context.uniqueIdentifier)
        saved[command.id] = nil
        save(saved, for: context.uniqueIdentifier)
        if let shortcut = defaults[context.uniqueIdentifier]?[command.id] {
            command.apply(shortcut)
        }
    }

    /// Copies the shortcuts of an installation to the installation that replaces it in an update.
    public func copyShortcutsForUpdate(from oldIdentifier: String, to newIdentifier: String) {
        let saved = savedShortcuts(for: oldIdentifier)
        guard !saved.isEmpty else { return }
        save(saved, for: newIdentifier)
    }

    /// Removes the shortcuts of an installation.
    public func removeShortcuts(for identifier: String) {
        defaults[identifier] = nil
        do {
            try keyValueStore.removeObject(forKey: key(for: identifier))
        } catch {
            Logger.webExtensions.error("Could not remove extension shortcuts: \(error.localizedDescription)")
        }
    }

    private func captureDefaults(of context: WKWebExtensionContext) {
        guard defaults[context.uniqueIdentifier] == nil else { return }
        var shortcuts: [String: WebExtensionCommandShortcut] = [:]
        for command in context.commands {
            shortcuts[command.id] = WebExtensionCommandShortcut(activationKey: command.activationKey, modifierFlags: command.modifierFlags)
        }
        defaults[context.uniqueIdentifier] = shortcuts
    }

    private func savedShortcuts(for identifier: String) -> [String: WebExtensionCommandShortcut] {
        do {
            guard let data = try keyValueStore.object(forKey: key(for: identifier)) as? Data else { return [:] }
            return try JSONDecoder().decode([String: WebExtensionCommandShortcut].self, from: data)
        } catch {
            Logger.webExtensions.error("Could not read extension shortcuts: \(error.localizedDescription)")
            return [:]
        }
    }

    private func save(_ shortcuts: [String: WebExtensionCommandShortcut], for identifier: String) {
        do {
            if shortcuts.isEmpty {
                try keyValueStore.removeObject(forKey: key(for: identifier))
            } else {
                try keyValueStore.set(JSONEncoder().encode(shortcuts), forKey: key(for: identifier))
            }
        } catch {
            Logger.webExtensions.error("Could not save extension shortcuts: \(error.localizedDescription)")
        }
    }

    private func key(for identifier: String) -> String {
        "\(Self.keyPrefix).\(identifier)"
    }
}

@available(macOS 15.4, *)
private extension WKWebExtension.Command {
    @MainActor
    func apply(_ shortcut: WebExtensionCommandShortcut) {
        activationKey = shortcut.activationKey
        modifierFlags = NSEvent.ModifierFlags(rawValue: shortcut.modifierFlags)
    }
}
#endif
