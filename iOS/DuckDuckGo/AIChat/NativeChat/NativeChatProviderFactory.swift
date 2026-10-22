//
//  NativeChatProviderFactory.swift
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

import DuckAIChatCore
import DuckAIChatMLX
import DuckAIChatProviders
import Foundation
import UIKit

/// One MLX provider per model, so a loaded model is shared by every surface and job that uses it.
@MainActor
enum NativeChatProviderFactory {
    static let modelStore = ModelStore()
    private static var mlxProviders: [String: MLXProvider] = [:]

    /// The provider for one job. A job on Automatic follows chat; chat on Automatic picks by device.
    static func makeProvider(for task: DuckAINativeSettings.LocalTask) -> any ChatProvider {
        provider(for: resolvedModel(for: task), task: task)
    }

    static func provider(for model: DuckAINativeSettings.TaskModel, task: DuckAINativeSettings.LocalTask) -> any ChatProvider {
        switch model {
        case .automatic, .stub:
            if task == .suggestedPrompts { return suggestionsStub() }
            return StubProvider(configuration: .init(unevenBursts: UserDefaults.standard.bool(forKey: "duckAINative.stub.unevenBursts")))
        case .foundationModels:
            return foundationModels() ?? StubProvider()
        case .mlx(let id):
            return mlxProvider(ModelCatalog.model(withID: id) ?? recommendedMLXModel)
        }
    }

    static func resolvedModel(for task: DuckAINativeSettings.LocalTask) -> DuckAINativeSettings.TaskModel {
        let models = DuckAINativeSettings.shared.taskModels
        if let model = models[task], model != .automatic { return model }
        if task != .chat, let chat = models[.chat], chat != .automatic { return chat }
#if targetEnvironment(simulator)
        return .stub
#else
        return .mlx(id: recommendedMLXModel.id)
#endif
    }

    static var isFoundationModelsAvailable: Bool {
        guard let provider = foundationModels() else { return false }
        if case .unsupported = provider.availability { return false }
        return true
    }

    /// The stub answers suggestion requests in the shape a suggestions model would, so the local path can be seen
    /// working without a device.
    private static func suggestionsStub() -> StubProvider {
        let reply = """
        What are the key points of this page?
        Who is this page written for?
        Can you explain the main idea simply?
        What should I read next on this topic?

        """
        return StubProvider(configuration: .init(reply: reply, wordsPerSecond: 60,
                                                 loadTime: .milliseconds(200), readTime: .milliseconds(200)))
    }

    private static var memoryWarningObserver: NSObjectProtocol?

    static var recommendedMLXModel: Model {
        ModelCatalog.recommended(physicalMemory: ProcessInfo.processInfo.physicalMemory)
    }

    private static func mlxProvider(_ model: Model) -> MLXProvider {
        if let existing = mlxProviders[model.id] { return existing }
        let provider = MLXProvider(model: model, store: modelStore)
        mlxProviders[model.id] = provider
        if memoryWarningObserver == nil {
            memoryWarningObserver = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
                                                                           object: nil, queue: .main) { _ in
                Task { @MainActor in mlxProviders.values.forEach { $0.unload() } }
            }
        }
        return provider
    }

    private static func foundationModels() -> (any ChatProvider)? {
#if canImport(FoundationModels)
        if #available(iOS 26, *) {
            return FoundationModelsProvider()
        }
#endif
        return nil
    }
}
