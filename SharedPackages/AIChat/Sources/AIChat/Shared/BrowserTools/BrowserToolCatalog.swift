//
//  BrowserToolCatalog.swift
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

/// The browser tools Duck.ai may discover and invoke, after remote-config gating.
///
/// A tool whose sub-feature is off is absent from `tools/list` *and* unresolvable by name, so
/// calling it anyway reports `unavailable` rather than running.
@MainActor
public final class BrowserToolCatalog {

    private let orderedTools: [any BrowserTool]
    private let toolsByName: [String: any BrowserTool]
    private let configuration: BrowserToolsConfiguration

    /// - Parameter tools: registration order is the order the front end sees, so it stays stable
    ///   across launches rather than following dictionary ordering.
    public init(tools: [any BrowserTool], configuration: BrowserToolsConfiguration) {
        self.orderedTools = tools
        self.configuration = configuration
        self.toolsByName = Dictionary(tools.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        assert(tools.count == toolsByName.count, "Browser tool names must be unique")
    }

    /// Enabled tools, in registration order. Empty when the parent feature is off.
    public var enabledTools: [any BrowserTool] {
        guard configuration.isEnabled else { return [] }
        return orderedTools.filter { configuration.isToolEnabled(named: $0.name) }
    }

    /// Resolves a tool for invocation. `nil` covers an unknown name and a disabled sub-feature
    /// alike — both are `unavailable` to the caller.
    public func tool(named name: String) -> (any BrowserTool)? {
        guard configuration.isEnabled, let tool = toolsByName[name] else { return nil }
        return configuration.isToolEnabled(named: name) ? tool : nil
    }
}
