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

enum UnifiedToggleInputAttachment: Identifiable {
    case image(AIChatImageAttachment)
    case file(AIChatFileAttachment)

    var id: UUID {
        switch self {
        case .image(let attachment):
            return attachment.id
        case .file(let attachment):
            return attachment.id
        }
    }

    var fileName: String {
        switch self {
        case .image(let attachment):
            return attachment.fileName
        case .file(let attachment):
            return attachment.fileName
        }
    }

    var fileSizeBytes: Int {
        switch self {
        case .image:
            return 0
        case .file(let attachment):
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
        if case .file = self {
            return true
        }
        return false
    }

    var image: UIImage? {
        guard case .image(let attachment) = self else { return nil }
        return attachment.image
    }

    var fileExtensionDisplayName: String? {
        guard case .file = self else { return nil }
        let pathExtension = (fileName as NSString).pathExtension
        guard !pathExtension.isEmpty else { return nil }
        return pathExtension.uppercased()
    }
}
