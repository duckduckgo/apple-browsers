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

/// One MLX provider for the app's lifetime, so a loaded model is shared by every surface.
@MainActor
enum NativeChatProviderFactory {
    private static let modelStore = ModelStore()
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

    private static var memoryWarningObserver: NSObjectProtocol?

    private static func mlxProvider() -> MLXProvider {
        if let mlx { return mlx }
        let provider = MLXProvider(store: modelStore)
        mlx = provider
        memoryWarningObserver = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
                                                                       object: nil, queue: .main) { _ in
            provider.unload()
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
