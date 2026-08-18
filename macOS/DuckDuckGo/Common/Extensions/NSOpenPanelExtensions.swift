//
//  NSOpenPanelExtensions.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

import AppKit
import UniformTypeIdentifiers

extension NSOpenPanel {

    static func downloadDirectoryPanel(downloadsPreferences: DownloadsPreferences) -> NSOpenPanel {
        let panel = NSOpenPanel()

        panel.directoryURL = downloadsPreferences.effectiveDownloadLocation
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true

        return panel
    }

    /// Panel asking the user to pick a directory so the app is granted access to it.
    static func directoryAccessPanel(directoryURL: URL, message: String, prompt: String) -> NSOpenPanel {
        let panel = NSOpenPanel()

        panel.directoryURL = directoryURL
        panel.message = message
        panel.prompt = prompt
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        return panel
    }

    convenience init(allowedFileTypes: [UTType], directoryURL: URL? = nil) {
        self.init()

        self.directoryURL = directoryURL
        canChooseFiles = true
        allowedContentTypes = allowedFileTypes
        canChooseDirectories = false
    }

    static func openFilePanel() -> NSOpenPanel {
        let panel = NSOpenPanel()

        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            .plainText,     // Plain text files
            .html,          // HTML files  
            .pdf,           // PDF files
            .webArchive,    // Web archive files
            .jpeg,          // JPEG images
            .png,           // PNG images
            .gif,           // GIF images
            .svg,           // SVG images
            .webP           // WebP images
        ]

        return panel
    }

}
