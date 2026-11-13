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

    convenience init(featureFlagger: FeatureFlagger,
                     storage: AIChatPageSummariesModelStoring,
                     engine: AIChatLocalModelEngine = AppleFoundationModelEngine(),
                     notificationCenter: NotificationCenter = .default) {
        self.init(isFeatureFlagOn: { featureFlagger.isFeatureOn(.aiChatLocalModels) },
                  featureFlagUpdates: featureFlagger.updatesPublisher,
                  storage: storage,
                  engine: engine,
                  notificationCenter: notificationCenter)
    }
}

/// Asks whether Duck.ai may use the local model.
@MainActor
public protocol LocalModelAccessAsking: AnyObject {
    /// - Parameter window: The window of the page that asked. The prompt goes over everything in it.
    func ask(in window: UIWindow?, modelName: String) async -> AIChatLocalModelAccessReply.Result
}

/// One for the whole app: only one run may use the model at a time, every Duck.ai page must see the
/// same state, and a second request while the prompt is up must get the same answer.
public struct AIChatLocalModelDependencies {
    public let service: AIChatLocalModelService
    public let accessPrompt: LocalModelAccessAsking

    public init(service: AIChatLocalModelService, accessPrompt: LocalModelAccessAsking) {
        self.service = service
        self.accessPrompt = accessPrompt
    }
}
