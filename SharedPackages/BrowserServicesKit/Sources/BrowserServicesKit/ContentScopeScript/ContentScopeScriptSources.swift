//
//  ContentScopeScriptSources.swift
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
import TrackerRadarKit

/// The page-world and isolated Content Scope Scripts sources that every tab of one content-blocking update shares.
///
/// Each source is generated once, on first use or when `build()` is called, from any thread. Call `build()` where the
/// update is assembled, off the main thread, so that no tab generates them.
public final class ContentScopeScriptSources: @unchecked Sendable {

    public typealias FailureHandler = (Error) -> Never

    private let privacyConfigurationManager: PrivacyConfigurationManaging
    private let properties: ContentScopeProperties
    private let surrogateTrackerData: TrackerData?
    private let contentScopeExcludedFeatures: [String]
    private let contentScopeIsolatedExcludedFeatures: [String]
    private let onFailure: FailureHandler

    private let lock = NSLock()
    private var builtContentScope: ContentScopeScriptSource?
    private var builtContentScopeIsolated: ContentScopeScriptSource?

    /// - Parameters:
    ///   - contentScopeExcludedFeatures: Features left out of the page-world script's configuration.
    ///   - contentScopeIsolatedExcludedFeatures: Features left out of the isolated script's configuration.
    ///   - onFailure: Called when a bundle can't be loaded, which leaves the browser without protections.
    public init(privacyConfigurationManager: PrivacyConfigurationManaging,
                properties: ContentScopeProperties,
                surrogateTrackerData: TrackerData?,
                contentScopeExcludedFeatures: [String],
                contentScopeIsolatedExcludedFeatures: [String] = ContentScopePrivacyConfigurationJSONGenerator.defaultExcludedFeatures,
                onFailure: @escaping FailureHandler) {
        self.privacyConfigurationManager = privacyConfigurationManager
        self.properties = properties
        self.surrogateTrackerData = surrogateTrackerData
        self.contentScopeExcludedFeatures = contentScopeExcludedFeatures
        self.contentScopeIsolatedExcludedFeatures = contentScopeIsolatedExcludedFeatures
        self.onFailure = onFailure
    }

    public var contentScope: ContentScopeScriptSource {
        lock.withLock {
            if let builtContentScope { return builtContentScope }
            let source = makeSource(scriptContext: .contentScope(surrogateTrackerData: surrogateTrackerData),
                                    excludedFeatures: contentScopeExcludedFeatures)
            builtContentScope = source
            return source
        }
    }

    public var contentScopeIsolated: ContentScopeScriptSource {
        lock.withLock {
            if let builtContentScopeIsolated { return builtContentScopeIsolated }
            let source = makeSource(scriptContext: .contentScopeIsolated, excludedFeatures: contentScopeIsolatedExcludedFeatures)
            builtContentScopeIsolated = source
            return source
        }
    }

    /// Generates both sources and wraps them for injection on the calling thread, which should not be the main thread.
    public func build() {
        contentScope.prepareForInjection()
        contentScopeIsolated.prepareForInjection()
    }

    private func makeSource(scriptContext: ContentScopeScriptContext, excludedFeatures: [String]) -> ContentScopeScriptSource {
        do {
            let generator = ContentScopePrivacyConfigurationJSONGenerator(privacyConfigurationManager: privacyConfigurationManager,
                                                                          excludedFeatures: excludedFeatures)
            return try ContentScopeScriptSource(privacyConfigurationManager: privacyConfigurationManager,
                                                properties: properties,
                                                scriptContext: scriptContext,
                                                privacyConfigurationJSONGenerator: generator)
        } catch {
            onFailure(error)
        }
    }
}
