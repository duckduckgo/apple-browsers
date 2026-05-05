//
//  AIChatFileAttachment.swift
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

public struct AIChatFileAttachment: Identifiable, Sendable {
    public let id: UUID
    public let data: Data
    public let fileName: String
    public let mimeType: String
    public let fileSizeBytes: Int
    public let pageCount: Int?
    public let isEncrypted: Bool

    public init(
        id: UUID = UUID(),
        data: Data,
        fileName: String,
        mimeType: String,
        fileSizeBytes: Int? = nil,
        pageCount: Int? = nil,
        isEncrypted: Bool = false
    ) {
        self.id = id
        self.data = data
        self.fileName = fileName
        self.mimeType = mimeType
        self.fileSizeBytes = fileSizeBytes ?? data.count
        self.pageCount = pageCount
        self.isEncrypted = isEncrypted
    }
}
