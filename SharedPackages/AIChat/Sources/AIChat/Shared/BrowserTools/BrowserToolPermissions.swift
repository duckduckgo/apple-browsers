//
//  BrowserToolPermissions.swift
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

import Foundation
import Persistence

public enum BrowserToolPermissionState: String, Equatable, Sendable {
    case ask
    case allow
    case deny
}

@MainActor
public protocol BrowserToolPermissionStoring: AnyObject {
    /// `nil` when the tool follows its default.
    func state(forToolNamed name: String) -> BrowserToolPermissionState?
    func setState(_ state: BrowserToolPermissionState?, forToolNamed name: String)

    var storedDecisions: [String: BrowserToolPermissionState] { get }
    func clearAll()
}

public extension BrowserToolPermissionStoring {

    func effectiveState(for tool: any BrowserTool) -> BrowserToolPermissionState {
        let state = state(forToolNamed: tool.name) ?? tool.permissionMode.defaultState
        return tool.asksEveryTime && state == .allow ? .ask : state
    }
}

public extension BrowserToolPermissionMode {
    var defaultState: BrowserToolPermissionState {
        self == .auto ? .allow : .ask
    }
}

enum BrowserToolPermissionStorageKey: String, StorageKeyDescribing {
    // Dot-free on purpose: dots break UserDefaults KVO, and `StorageKey` asserts on them.
    case decisions = "ai-chat_browser-tool-permissions"
}

public struct BrowserToolPermissionStorageKeys: StoringKeys {
    public let decisions = StorageKey<[String: String]>(BrowserToolPermissionStorageKey.decisions)
    public init() {}
}

/// `[toolName: "allow" | "deny"]` under one key, the layout Windows persists. iOS stores decisions here;
/// macOS keeps them in its site permissions.
@MainActor
public final class BrowserToolPermissionStore: BrowserToolPermissionStoring {

    private let storage: any KeyedStoring<BrowserToolPermissionStorageKeys>

    public init(storage: any KeyedStoring<BrowserToolPermissionStorageKeys>) {
        self.storage = storage
    }

    public func state(forToolNamed name: String) -> BrowserToolPermissionState? {
        Self.parse(decisions[name])
    }

    public func setState(_ state: BrowserToolPermissionState?, forToolNamed name: String) {
        var decisions = decisions
        decisions[name] = state.flatMap { $0 == .ask ? nil : $0.rawValue }
        self.decisions = decisions
    }

    public var storedDecisions: [String: BrowserToolPermissionState] {
        decisions.compactMapValues(Self.parse)
    }

    public func clearAll() {
        storage.decisions = nil
    }

    private var decisions: [String: String] {
        get { storage.decisions ?? [:] }
        set { storage.decisions = newValue.isEmpty ? nil : newValue }
    }

    /// Anything unrecognised reads as no decision, so a bad value can only ever cause an extra prompt.
    private static func parse(_ value: String?) -> BrowserToolPermissionState? {
        switch value {
        case BrowserToolPermissionState.allow.rawValue: .allow
        case BrowserToolPermissionState.deny.rawValue: .deny
        default: nil
        }
    }
}
