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

/// One MLX provider per selected model, so a loaded model is shared by every surface until the selection changes.
@MainActor
enum NativeChatProviderFactory {
    static let modelStore = ModelStore()
    private static var mlx: MLXProvider?

    static func makeProvider(_ choice: DuckAINativeSettings.ProviderChoice = DuckAINativeSettings.shared.provider) -> any ChatProvider {
        switch choice {
        case .stub:
            return StubProvider()
        case .foundationModels:
            return foundationModels() ?? StubProvider()
        case .mlx:
            return mlxProvider()
        case .automatic:
#if targetEnvironment(simulator)
            return StubProvider()
#else
            return mlxProvider()
#endif
        }
    }

    /// Suggested prompts use the chat's provider, except that the stub answers in the shape a suggestions model would,
    /// so the local path can be seen working without a device.
    static func makeSuggestionsProvider(_ choice: DuckAINativeSettings.ProviderChoice = DuckAINativeSettings.shared.provider) -> any ChatProvider {
        let provider = makeProvider(choice)
        guard provider is StubProvider else { return provider }
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

    static var selectedMLXModel: Model {
        DuckAINativeSettings.shared.mlxModelID.flatMap(ModelCatalog.model(withID:))
            ?? ModelCatalog.recommended(physicalMemory: ProcessInfo.processInfo.physicalMemory)
    }

    private static func mlxProvider() -> MLXProvider {
        let model = selectedMLXModel
        if let mlx, mlx.descriptor.id.rawValue == model.id { return mlx }
        mlx?.unload()
        let provider = MLXProvider(model: model, store: modelStore)
        mlx = provider
        if memoryWarningObserver == nil {
            memoryWarningObserver = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
                                                                           object: nil, queue: .main) { _ in
                Task { @MainActor in mlx?.unload() }
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
