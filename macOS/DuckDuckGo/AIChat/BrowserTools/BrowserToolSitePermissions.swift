//
//  BrowserToolSitePermissions.swift
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

import AIChat
import Foundation

/// Remembered Always / Never choices for browser tools, kept as site permissions of Duck.ai's own site,
/// so one choice applies to every Duck.ai page, sidebar and chat.
@MainActor
final class BrowserToolSitePermissions: BrowserToolPermissionStoring {

    static var domain: String { URL.duckAi.host ?? "duck.ai" }

    private let permissionManager: PermissionManagerProtocol

    init(permissionManager: PermissionManagerProtocol) {
        self.permissionManager = permissionManager
    }

    func state(forToolNamed name: String) -> BrowserToolPermissionState {
        switch permissionManager.persistedDecision(forDomain: Self.domain, permissionType: .browserTool(name: name)) {
        case .allow: .allow
        case .deny: .deny
        case .ask, nil: .ask
        }
    }

    func setState(_ state: BrowserToolPermissionState, forToolNamed name: String) {
        switch state {
        case .ask: permissionManager.removePermission(forDomain: Self.domain, permissionType: .browserTool(name: name))
        case .allow: permissionManager.setPermission(.allow, forDomain: Self.domain, permissionType: .browserTool(name: name))
        case .deny: permissionManager.setPermission(.deny, forDomain: Self.domain, permissionType: .browserTool(name: name))
        }
    }

    var storedDecisions: [String: BrowserToolPermissionState] {
        permissionManager.persistedPermissionTypes(forDomain: Self.domain).reduce(into: [:]) { result, type in
            guard case .browserTool(let name) = type else { return }
            let state = state(forToolNamed: name)
            if state != .ask { result[name] = state }
        }
    }

    func clearAll() {
        for name in storedDecisions.keys {
            setState(.ask, forToolNamed: name)
        }
    }
}
