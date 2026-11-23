//
//  ContentScopeScriptSource.swift
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
import PrivacyConfig
import UserScript

/// The Content Scope Scripts source for one script context, generated once and shared by every `ContentScopeUserScript` made from it.
///
/// Generating the source embeds the privacy configuration, up to about 1 MB, in the bundle, which takes milliseconds,
/// and each copy of the source costs that much memory again. Build one per content-blocking update, off the main thread,
/// and give it to every tab: they then share the source and its `WKUserScript`, which are released with the update.
public final class ContentScopeScriptSource: @unchecked Sendable {

    public let scriptContext: ContentScopeScriptContext
    /// Whether the script's message broker logs messages, from `ContentScopeProperties.debug`.
    public let isDebug: Bool
    let userScript: SharedWKUserScript

    public var source: String { userScript.source }

    /// Generates the source on the calling thread.
    ///
    /// - Parameter privacyConfigurationJSONGenerator: The configuration to embed. When `nil`, the whole current configuration is embedded.
    public init(privacyConfigurationManager: PrivacyConfigurationManaging,
                properties: ContentScopeProperties,
                scriptContext: ContentScopeScriptContext,
                privacyConfigurationJSONGenerator: CustomisedPrivacyConfigurationJSONGenerating?) throws {
        self.scriptContext = scriptContext
        self.isDebug = properties.debug
        let source = try ContentScopeUserScript.generateSource(privacyConfigurationManager,
                                                               properties: properties,
                                                               scriptContext: scriptContext,
                                                               privacyConfigurationJSONGenerator: privacyConfigurationJSONGenerator)
        self.userScript = SharedWKUserScript(source: source,
                                             injectionTime: ContentScopeUserScript.injectionTime,
                                             forMainFrameOnly: ContentScopeUserScript.forMainFrameOnly,
                                             requiresRunInPageContentWorld: !scriptContext.isIsolated)
    }

    /// Generates the source and wraps it for injection on a background thread.
    ///
    /// - Parameter privacyConfigurationJSONGenerator: The configuration to embed. When `nil`, the whole current configuration is embedded.
    public static func make(privacyConfigurationManager: PrivacyConfigurationManaging,
                            properties: ContentScopeProperties,
                            scriptContext: ContentScopeScriptContext,
                            privacyConfigurationJSONGenerator: CustomisedPrivacyConfigurationJSONGenerating?) async throws -> ContentScopeScriptSource {
        try await Task.detached(priority: .userInitiated) {
            let source = try ContentScopeScriptSource(privacyConfigurationManager: privacyConfigurationManager,
                                                      properties: properties,
                                                      scriptContext: scriptContext,
                                                      privacyConfigurationJSONGenerator: privacyConfigurationJSONGenerator)
            source.prepareForInjection()
            return source
        }.value
    }

    /// Wraps the source for injection now, so that the first tab to install it doesn't do that on the main thread.
    ///
    /// Call this from a background thread.
    public func prepareForInjection() {
        userScript.prepare()
    }
}
