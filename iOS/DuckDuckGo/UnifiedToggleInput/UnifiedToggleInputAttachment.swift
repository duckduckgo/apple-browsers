//
//  UnifiedToggleInputAttachment.swift
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
import Foundation
import UIKit

struct UnifiedToggleInputInvalidFileAttachment: Identifiable {
    let id: UUID
    let fileName: String
    let mimeType: String
    let fileSizeBytes: Int
    let validationMessage: String
    let sourceURL: URL?

    init(
        id: UUID = UUID(),
        fileName: String,
        mimeType: String,
        fileSizeBytes: Int,
        validationMessage: String,
        sourceURL: URL? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.mimeType = mimeType
        self.fileSizeBytes = fileSizeBytes
        self.validationMessage = validationMessage
        self.sourceURL = sourceURL
    }
}

enum UnifiedToggleInputAttachment: Identifiable {
    case image(AIChatImageAttachment)
    case file(AIChatFileAttachment)
    case invalidFile(UnifiedToggleInputInvalidFileAttachment)

    var id: UUID {
        switch self {
        case .image(let attachment):
            return attachment.id
        case .file(let attachment):
            return attachment.id
        case .invalidFile(let attachment):
            return attachment.id
        }
    }

    var fileName: String {
        switch self {
        case .image(let attachment):
            return attachment.fileName
        case .file(let attachment):
            return attachment.fileName
        case .invalidFile(let attachment):
            return attachment.fileName
        }
    }

    var fileSizeBytes: Int {
        switch self {
        case .image:
            return 0
        case .file(let attachment):
            return attachment.fileSizeBytes
        case .invalidFile(let attachment):
            return attachment.fileSizeBytes
        }
    }

    var isImage: Bool {
        if case .image = self {
            return true
        }
        return false
    }

    var isFile: Bool {
        switch self {
        case .file, .invalidFile:
            return true
        case .image:
            return false
        }
    }

    var isInvalid: Bool {
        if case .invalidFile = self {
            return true
        }
        return false
    }

    var validationMessage: String? {
        guard case .invalidFile(let attachment) = self else { return nil }
        return attachment.validationMessage
    }

    var fileAttachment: AIChatFileAttachment? {
        guard case .file(let attachment) = self else { return nil }
        return attachment
    }

    var mimeType: String? {
        switch self {
        case .image:
            return nil
        case .file(let attachment):
            return attachment.mimeType
        case .invalidFile(let attachment):
            return attachment.mimeType
        }
    }

    var image: UIImage? {
        guard case .image(let attachment) = self else { return nil }
        return attachment.image
    }

}
