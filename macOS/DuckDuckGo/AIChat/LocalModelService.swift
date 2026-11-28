//
//  LocalModelService.swift
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
import AppKitExtensions
import FeatureFlags_macOS
import Foundation
import PrivacyConfig

extension AIChatLocalModelService {

    /// - Parameter downloadableModel: Nil offers only Apple Intelligence.
    convenience init(featureFlagger: FeatureFlagger,
                     storage: AIChatPreferencesStorage = DefaultAIChatPreferencesStorage(),
                     engine: AIChatLocalModelEngine = AppleFoundationModelEngine(),
                     downloadableModel: AIChatDownloadableLocalModel? = nil,
                     engineOverride: LocalModelEngineOverridePersistor = LocalModelEngineOverridePersistor(),
                     notificationCenter: NotificationCenter = .default,
                     instrumentation: AIChatLocalModelInstrumentation = LocalModelPixelInstrumentation()) {
        self.init(isFeatureFlagOn: { featureFlagger.isFeatureOn(.aiChatLocalModels) },
                  featureFlagUpdates: featureFlagger.updatesPublisher,
                  storage: storage,
                  engine: engine,
                  downloadableModel: downloadableModel,
                  engineOverride: { engineOverride.current.engineKind },
                  engineOverrideUpdates: engineOverride.updates,
                  notificationCenter: notificationCenter,
                  instrumentation: instrumentation)
    }
}

extension AIChatDownloadableLocalModel {

    /// The model for Macs without Apple Intelligence: the one remote config names, or Gemma 4 E2B,
    /// on the llama.cpp framework the app bundles.
    @MainActor
    static func llamaCpp(privacyConfigurationManager: PrivacyConfigurationManaging) -> AIChatDownloadableLocalModel {
        let settings = privacyConfigurationManager.privacyConfig.settings(for: AIChatSubfeature.localModels)
        let spec = AIChatLocalModelSpec.fromRemoteSettings(settings) ?? .gemma4E2B
        let directory = URL.sandboxApplicationSupportURL.appendingPathComponent("LocalModels/LlamaCpp", isDirectory: true)
        let engine = AIChatLlamaEngine(model: spec.info, runtime: BundledLlamaRuntime()) {
            AIChatLocalModelDownloader.installedFileURL(in: directory, spec: spec)
        }
        return AIChatDownloadableLocalModel(engine: engine,
                                            installer: AIChatLocalModelDownloader(spec: spec, directory: directory))
    }
}
