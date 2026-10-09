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
/// to the app. The store saves the user's shortcuts per extension and command, and applies them
/// again each time an extension loads.
@available(macOS 15.4, *)
@MainActor
public final class WebExtensionCommandShortcutStore {

    private static let userDefaultsKey = "com.duckduckgo.web-extensions.command-shortcuts"

    private let userDefaults: UserDefaults
    /// The manifest shortcut of each command, by extension and command, captured before the first
    /// change, so a command can go back to it.
    private var defaults: [String: [String: WebExtensionCommandShortcut]] = [:]

    nonisolated public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    /// Applies the saved shortcuts to the commands of `contexts`.
    public func apply(to contexts: Set<WKWebExtensionContext>) {
        let saved = savedShortcuts()
        for context in contexts {
            captureDefaults(of: context)
            for command in context.commands {
                if let shortcut = saved[context.uniqueIdentifier]?[command.id] {
                    command.apply(shortcut)
                }
            }
        }
    }

    /// Whether the user changed the shortcut of `command`.
    public func isCustomized(_ command: WKWebExtension.Command, in context: WKWebExtensionContext) -> Bool {
        savedShortcuts()[context.uniqueIdentifier]?[command.id] != nil
    }

    /// Sets and saves the shortcut of `command`.
    public func setShortcut(_ shortcut: WebExtensionCommandShortcut, for command: WKWebExtension.Command, in context: WKWebExtensionContext) {
        captureDefaults(of: context)
        var saved = savedShortcuts()
        saved[context.uniqueIdentifier, default: [:]][command.id] = shortcut
        save(saved)
        command.apply(shortcut)
    }

    /// Puts back the manifest shortcut of `command`.
    public func resetShortcut(for command: WKWebExtension.Command, in context: WKWebExtensionContext) {
        var saved = savedShortcuts()
        saved[context.uniqueIdentifier]?[command.id] = nil
        save(saved)
        if let shortcut = defaults[context.uniqueIdentifier]?[command.id] {
            command.apply(shortcut)
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

    private func savedShortcuts() -> [String: [String: WebExtensionCommandShortcut]] {
        guard let data = userDefaults.data(forKey: Self.userDefaultsKey) else { return [:] }
        return (try? JSONDecoder().decode([String: [String: WebExtensionCommandShortcut]].self, from: data)) ?? [:]
    }

    private func save(_ shortcuts: [String: [String: WebExtensionCommandShortcut]]) {
        userDefaults.set(try? JSONEncoder().encode(shortcuts), forKey: Self.userDefaultsKey)
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
