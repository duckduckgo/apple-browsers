//
//  AIChatPromptAttachments.swift
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

/// Everything a prompt carries besides its text, in wire form. A nil kind omits its key; an empty array sends `[]`.
public struct AIChatPromptAttachments: Equatable {
    public var images: [AIChatNativePrompt.NativePromptImage]?
    public var files: [AIChatNativePrompt.NativePromptFile]?
    public var textPasted: [AIChatNativePrompt.NativePromptPastedText]?

    public static var none: AIChatPromptAttachments { AIChatPromptAttachments() }

    public init(images: [AIChatNativePrompt.NativePromptImage]? = nil,
                files: [AIChatNativePrompt.NativePromptFile]? = nil,
                textPasted: [AIChatNativePrompt.NativePromptPastedText]? = nil) {
        self.images = images
        self.files = files
        self.textPasted = textPasted
    }

    public var isEmpty: Bool {
        (images?.isEmpty ?? true) && (files?.isEmpty ?? true) && (textPasted?.isEmpty ?? true)
    }
}
