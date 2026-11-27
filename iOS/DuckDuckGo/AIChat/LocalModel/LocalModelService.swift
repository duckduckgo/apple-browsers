//
//  LocalModelService.swift
//  DuckDuckGo
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
import FeatureFlags_iOS
import Foundation
import PrivacyConfig
import UIKit

extension AIChatLocalModelService {

    /// - Parameter downloadableModel: Nil offers only Apple Intelligence.
    convenience init(featureFlagger: FeatureFlagger,
                     storage: AIChatPageSummariesModelStoring,
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

/// The model for iPhones and iPads without Apple Intelligence: the one remote config names, or
/// Gemma 4 E2B, on the llama.cpp framework the app bundles.
@MainActor
struct DownloadableLlamaModel {

    /// 6 GB devices report a little under 6 GB, and 4 GB ones under 4 GB. 4 GB devices haven't
    /// been tried.
    static let minimumPhysicalMemory: UInt64 = 5 * 1_073_741_824

    let model: AIChatDownloadableLocalModel
    let lifecycle: DownloadableLocalModelLifecycle

    init(privacyConfigurationManager: PrivacyConfigurationManaging) {
        let settings = privacyConfigurationManager.privacyConfig.settings(for: AIChatSubfeature.localModels)
        let spec = AIChatLocalModelSpec.fromRemoteSettings(settings) ?? .gemma4E2B
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = applicationSupport.appendingPathComponent("LocalModels/LlamaCpp", isDirectory: true)
        let engine = AIChatLlamaEngine(model: spec.info, runtime: BundledLlamaRuntime(minimumPhysicalMemory: Self.minimumPhysicalMemory)) {
            AIChatLocalModelDownloader.installedFileURL(in: directory, spec: spec)
        }
        let installer = AIChatLocalModelDownloader(spec: spec, directory: directory)
        model = AIChatDownloadableLocalModel(engine: engine, installer: installer)
        lifecycle = DownloadableLocalModelLifecycle(installer: installer,
                                                    unloadModel: engine.unloadModel,
                                                    openRuntime: engine.prepare)
    }
}

/// Asks whether Duck.ai may use the local model.
@MainActor
public protocol LocalModelAccessAsking: AnyObject {
    /// `.allowed` means Turn On for a model on the device, or Install for one that needs a download.
    /// - Parameter window: The window of the page that asked. The prompt goes over everything in it.
    func ask(in window: UIWindow?, request: AIChatLocalModelAccessRequest) async -> AIChatLocalModelAccessReply.Result
}

/// One for the whole app: only one run may use the model at a time, every Duck.ai page must see the
/// same state, and a second request while the prompt is up must get the same answer.
public struct AIChatLocalModelDependencies {
    public let service: AIChatLocalModelService
    public let accessPrompt: LocalModelAccessAsking
    /// Held for as long as the service, which runs the model it looks after.
    public let downloadableModelLifecycle: DownloadableLocalModelLifecycle?

    public init(service: AIChatLocalModelService,
                accessPrompt: LocalModelAccessAsking,
                downloadableModelLifecycle: DownloadableLocalModelLifecycle? = nil) {
        self.service = service
        self.accessPrompt = accessPrompt
        self.downloadableModelLifecycle = downloadableModelLifecycle
    }
}
