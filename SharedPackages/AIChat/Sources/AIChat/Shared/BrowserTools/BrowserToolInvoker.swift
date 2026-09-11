//
//  BrowserToolInvoker.swift
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

/// The single entry point for running a tool. Every reason a call can be refused lives here, in a
/// fixed order, so a tool's `execute` only handles its own arguments.
@MainActor
public final class BrowserToolInvoker {

    private let catalog: BrowserToolCatalog
    private let configuration: BrowserToolsConfiguration

    public init(catalog: BrowserToolCatalog, configuration: BrowserToolsConfiguration) {
        self.catalog = catalog
        self.configuration = configuration
    }

    public func invoke(toolNamed name: String,
                       arguments: JSONValue?,
                       context: BrowserToolCallContext) async -> BrowserToolResult {
        guard configuration.isEnabled else { return .failure(.unavailable) }

        // Covers an unknown name and a disabled sub-feature alike: the front end learns only that
        // the capability is not available here, not which of the two it was.
        guard let tool = catalog.tool(named: name) else { return .failure(.unavailable) }

        // Reported as plain `unavailable`, never a Fire-specific token. Checked before consent so a
        // call that can never succeed here cannot persist a decision.
        guard !context.isBurner else { return .failure(.unavailable) }

        assert(tool.permissionMode == .auto, "Ask-mode tools need consent, which does not exist yet")

        return await tool.execute(arguments: arguments, context: context)
    }
}
