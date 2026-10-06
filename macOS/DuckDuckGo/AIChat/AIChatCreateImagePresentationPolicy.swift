//
//  AIChatCreateImagePresentationPolicy.swift
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

struct AIChatCreateImagePresentationPolicy {
    let isImageGenerationEnabled: Bool
    let isUpdatedCreateImageEnabled: Bool
    let selectedModelSupportsImageGeneration: Bool
    let isOmnibarToolsEnabled: Bool
    let hasModelPickerContent: Bool
    let isImageGenerationMode: Bool

    var isImageGenerationItemVisible: Bool {
        isImageGenerationEnabled && (isUpdatedCreateImageEnabled || selectedModelSupportsImageGeneration)
    }

    var shouldShowModelPicker: Bool {
        guard isOmnibarToolsEnabled && hasModelPickerContent else { return false }
        return !isImageGenerationMode || isUpdatedCreateImageEnabled
    }

    var shouldMakeModelPickerReadOnly: Bool {
        isUpdatedCreateImageEnabled && isImageGenerationMode
    }
}
