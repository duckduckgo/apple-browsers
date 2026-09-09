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

/// The single entry point for running a browser tool.
///
/// Everything that can refuse a call lives here and runs in a fixed order, so a tool's `execute`
/// only has to worry about its own arguments.
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

        // The Fire boundary is checked before any consent evaluation, and reported as plain
        // `unavailable` rather than a Fire-specific token — so the front end cannot infer that the
        // user is browsing privately. Once consent exists (PR 2) this ordering also stops a call
        // that can never succeed in this window from persisting an Always/Never decision.
        guard !context.isBurner else { return .failure(.unavailable) }

        // Consent lands in PR 2. Until then every tool behaves as `auto`, which is why only `auto`
        // tools are registered in the catalog so far.
        assert(tool.permissionMode == .auto, "An ask-mode tool must not be registered before consent exists")

        return await tool.execute(arguments: arguments, context: context)
    }
}
