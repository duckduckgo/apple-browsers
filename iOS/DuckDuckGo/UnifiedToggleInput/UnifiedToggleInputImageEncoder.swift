//
//  UnifiedToggleInputImageEncoder.swift
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
import UIKit

enum UnifiedToggleInputImageEncoder {

    static func encode(_ attachments: [AIChatImageAttachment]) -> [AIChatNativePrompt.NativePromptImage]? {
        guard !attachments.isEmpty else { return nil }
        let images = attachments.compactMap { attachment -> AIChatNativePrompt.NativePromptImage? in
            let ext = (attachment.fileName as NSString).pathExtension.lowercased()
            let isJPEG = ext == "jpg" || ext == "jpeg"
            let data: Data?
            if isJPEG {
                data = attachment.image.jpegData(compressionQuality: 0.85)
            } else {
                data = attachment.image.pngData()
            }
            guard let data else { return nil }
            return AIChatNativePrompt.NativePromptImage(
                data: data.base64EncodedString(),
                format: isJPEG ? "jpeg" : "png"
            )
        }
        return images.isEmpty ? nil : images
    }
}
