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
import DuckAIChatCore

enum UnifiedToggleInputAttachmentEncoder {

    static func encodeNative(_ attachments: [UnifiedToggleInputAttachment], capabilities: InputCapabilities) throws -> AIChatPromptAttachments {
        guard !attachments.contains(where: { $0.fileAttachment != nil || $0.isInvalid }) else {
            throw ChatError.unknown("Files are unavailable in local chat.")
        }
        let images = attachments.compactMap { attachment -> UIImage? in
            if case .image(let value) = attachment { return value.image }
            return nil
        }
        if !images.isEmpty && capabilities.imageLimits == nil { throw ChatError.modelUnavailable(reason: "This model does not support images.") }
        let limits = ImageInputLimits.standard
        guard images.count <= limits.countPerTurn else { throw ChatError.unknown("Attach one image per message.") }
        let encoded = try images.map { image -> AIChatNativePrompt.NativePromptImage in
            guard image.size.width > 0, image.size.height > 0 else { throw ChatError.unknown("Invalid image.") }
            let pixels = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
            let scale = min(1, CGFloat(limits.longestDimension) / max(pixels.width, pixels.height))
            let size = CGSize(width: max(1, floor(pixels.width * scale)), height: max(1, floor(pixels.height * scale)))
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            let normalized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
            guard let data = normalized.jpegData(compressionQuality: 0.85), data.count <= limits.bytesPerImage else {
                throw ChatError.unknown("The image exceeds 2 MiB. Choose a smaller image.")
            }
            return AIChatNativePrompt.NativePromptImage(data: data.base64EncodedString(), format: "jpeg")
        }
        return AIChatPromptAttachments(images: encoded.isEmpty ? nil : encoded, textPasted: encodedPastedText(in: attachments))
    }

    static func encode(_ attachments: [UnifiedToggleInputAttachment],
                       imagesSupported: Bool,
                       filesSupported: Bool) -> AIChatPromptAttachments {
        let images = imagesSupported ? encodedImages(in: attachments) : []
        let files = filesSupported ? encodedFiles(in: attachments) : []
        let textPasted = encodedPastedText(in: attachments)
        return AIChatPromptAttachments(images: images.isEmpty ? nil : images,
                                       files: files.isEmpty ? nil : files,
                                       textPasted: textPasted.isEmpty ? nil : textPasted)
    }

    static func encodeForEdit(_ attachments: [UnifiedToggleInputAttachment],
                              imagesSupported: Bool,
                              filesSupported: Bool,
                              carriesPastedText: Bool) -> AIChatPromptAttachments {
        AIChatPromptAttachments(images: imagesSupported ? encodedImages(in: attachments) : nil,
                                files: filesSupported ? encodedFiles(in: attachments) : nil,
                                textPasted: carriesPastedText ? encodedPastedText(in: attachments) : nil)
    }

    private static func encodedPastedText(in attachments: [UnifiedToggleInputAttachment]) -> [AIChatNativePrompt.NativePromptPastedText] {
        attachments.compactMap { $0.pastedText?.payload }
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
