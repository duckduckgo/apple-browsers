//
//  UnifiedToggleInputAttachmentEncoder.swift
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

enum UnifiedToggleInputAttachmentEncoder {

    static func encode(_ attachments: [UnifiedToggleInputAttachment],
                       imagesSupported: Bool,
                       filesSupported: Bool) -> AIChatPromptAttachments {
        let images = imagesSupported ? encodedImages(in: attachments) : []
        let files = filesSupported ? encodedFiles(in: attachments) : []
        return AIChatPromptAttachments(images: images.isEmpty ? nil : images,
                                       files: files.isEmpty ? nil : files)
    }

    static func encodeForEdit(_ attachments: [UnifiedToggleInputAttachment],
                              imagesSupported: Bool,
                              filesSupported: Bool) -> AIChatPromptAttachments {
        AIChatPromptAttachments(images: imagesSupported ? encodedImages(in: attachments) : nil,
                                files: filesSupported ? encodedFiles(in: attachments) : nil)
    }

    private static func encodedImages(in attachments: [UnifiedToggleInputAttachment]) -> [AIChatNativePrompt.NativePromptImage] {
        attachments.compactMap { attachment in
            guard case .image(let imageAttachment) = attachment else { return nil }

            if let originalData = imageAttachment.originalEncodedData, let format = imageAttachment.originalFormat {
                return AIChatNativePrompt.NativePromptImage(data: originalData.base64EncodedString(), format: format)
            }
            if let jpegData = imageAttachment.image.jpegData(compressionQuality: 0.85) {
                return AIChatNativePrompt.NativePromptImage(data: jpegData.base64EncodedString(), format: "jpeg")
            }
            guard let pngData = imageAttachment.image.pngData() else { return nil }
            return AIChatNativePrompt.NativePromptImage(data: pngData.base64EncodedString(), format: "png")
        }
    }

    private static func encodedFiles(in attachments: [UnifiedToggleInputAttachment]) -> [AIChatNativePrompt.NativePromptFile] {
        attachments.compactMap { attachment in
            guard let fileAttachment = attachment.fileAttachment else { return nil }
            return AIChatNativePrompt.NativePromptFile(data: fileAttachment.data.base64EncodedString(),
                                                       fileName: fileAttachment.fileName,
                                                       mimeType: fileAttachment.mimeType)
        }
    }
}
