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

/// A stored decision for an `ask` tool. `ask` is the absence of one.
public enum BrowserToolPermissionState: String, Equatable, Sendable {
    case ask
    case allow
    case deny
}

@MainActor
public protocol BrowserToolPermissionStoring: AnyObject {
    func state(forToolNamed name: String) -> BrowserToolPermissionState

    /// `.ask` forgets the tool's decision.
    func setState(_ state: BrowserToolPermissionState, forToolNamed name: String)

    var storedDecisions: [String: BrowserToolPermissionState] { get }
    func clearAll()
}

public extension BrowserToolPermissionStoring {

    /// An `auto` tool is always allowed; only `ask` tools have a stored decision.
    func effectiveState(for tool: any BrowserTool) -> BrowserToolPermissionState {
        tool.permissionMode == .auto ? .allow : state(forToolNamed: tool.name)
    }
}
