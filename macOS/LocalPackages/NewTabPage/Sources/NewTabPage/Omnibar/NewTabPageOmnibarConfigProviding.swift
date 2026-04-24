//
//  NewTabPageOmnibarConfigProviding.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import Combine

public protocol NewTabPageOmnibarConfigProviding: AnyObject {

    @MainActor
    var mode: NewTabPageDataModel.OmnibarMode { get set }
    var modePublisher: AnyPublisher<NewTabPageDataModel.OmnibarMode, Never> { get }

    var isAIChatShortcutEnabled: Bool { get set }
    var isAIChatShortcutEnabledPublisher: AnyPublisher<Bool, Never> { get }

    var isAIChatSettingVisible: Bool { get }
    var isAIChatSettingVisiblePublisher: AnyPublisher<Bool, Never> { get }

    var showCustomizePopover: Bool { get set }

    var isAIChatRecentChatsEnabled: Bool { get }

    var showViewAllAiChats: Bool { get }
    var showViewAllAiChatsPublisher: AnyPublisher<Bool, Never> { get }

    var isAIChatToolsEnabled: Bool { get }

    var isImageGenerationEnabled: Bool { get }

    var isWebSearchEnabled: Bool { get }

    var selectedModelId: String? { get set }
    var selectedModelIdPublisher: AnyPublisher<String?, Never> { get }

    /// Short display name that the native omnibar can show before its own models fetch completes.
    /// Mirrors the native `AIChatPreferencesPersisting.selectedModelShortName`.
    var selectedModelShortName: String? { get set }

    /// Whether the reasoning-effort picker feature is available. Combines the dedicated
    /// reasoning-effort feature flag with `isAIChatToolsEnabled`, since reasoning effort depends
    /// on the model picker being available.
    var isReasoningEffortEnabled: Bool { get }

    /// The user's persisted reasoning effort (e.g. `"none"`, `"low"`, `"medium"`). `nil` when
    /// nothing is selected or when `isReasoningEffortEnabled` is false.
    var selectedReasoningEffort: String? { get set }
    var selectedReasoningEffortPublisher: AnyPublisher<String?, Never> { get }
}
