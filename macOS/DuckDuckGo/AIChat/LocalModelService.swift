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
import Combine
import FeatureFlags_macOS
import Foundation
import Persistence
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

    /// The model for Macs without Apple Intelligence: the one remote config names, or Granite 4.0 1B,
    /// on the llama.cpp framework the app bundles.
    @MainActor
    static func llamaCpp(privacyConfigurationManager: PrivacyConfigurationManaging) -> AIChatDownloadableLocalModel {
        let settings = privacyConfigurationManager.privacyConfig.settings(for: AIChatSubfeature.localModels)
        let spec = AIChatLocalModelSpec.fromRemoteSettings(settings) ?? .granite
        let directory = URL.sandboxApplicationSupportURL.appendingPathComponent("LocalModels/LlamaCpp", isDirectory: true)
        let engine = AIChatLlamaEngine(model: spec.info, runtime: BundledLlamaRuntime()) {
            AIChatLocalModelDownloader.installedFileURL(in: directory, spec: spec)
        }
        return AIChatDownloadableLocalModel(engine: engine,
                                            installer: AIChatLocalModelDownloader(spec: spec, directory: directory))
    }
}

/// Debug menu: which engine runs local summaries, on any Mac. Switching keeps the downloaded
/// model, so switching back is instant.
enum LocalModelEngineOverride: String, CaseIterable {
    case automatic
    case appleIntelligence
    case llama

    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .appleIntelligence: return "Apple Intelligence"
        case .llama: return "Downloadable Model (llama.cpp)"
        }
    }

    var engineKind: AIChatLocalModelEngineKind? {
        switch self {
        case .automatic: return nil
        case .appleIntelligence: return .appleIntelligence
        case .llama: return .llama
        }
    }
}

struct LocalModelEngineOverridePersistor {

    static let key = "aichat.localModel.engineOverride"
    static let didChangeNotification = Notification.Name("LocalModelEngineOverrideDidChange")

    private let keyValueStore: KeyValueStoring
    private let notificationCenter: NotificationCenter

    init(keyValueStore: KeyValueStoring = UserDefaults.standard, notificationCenter: NotificationCenter = .default) {
        self.keyValueStore = keyValueStore
        self.notificationCenter = notificationCenter
    }

    var current: LocalModelEngineOverride {
        get {
            (keyValueStore.object(forKey: Self.key) as? String).flatMap(LocalModelEngineOverride.init) ?? .automatic
        }
        nonmutating set {
            if newValue == .automatic {
                keyValueStore.removeObject(forKey: Self.key)
            } else {
                keyValueStore.set(newValue.rawValue, forKey: Self.key)
            }
            notificationCenter.post(name: Self.didChangeNotification, object: nil)
        }
    }

    var updates: AnyPublisher<Void, Never> {
        notificationCenter.publisher(for: Self.didChangeNotification).map { _ in () }.eraseToAnyPublisher()
    }
}
