//
//  UserText.swift
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

#if os(iOS)
import Foundation

public struct UserText {
    public static let aiChatTitle = NSLocalizedString("aichat.title", value: "Duck.ai", comment: "Title for DuckDuckGo AI Chat. Should not be translated")
    public static let downloadComplete = NSLocalizedString("aichat.download.complete", value: "Download complete for %@", comment: "Download complete for duck.ai")
    public static let downloadToastShow = NSLocalizedString("aichat.download.show", value: "Show", comment: "Show button for downloads")
    public static let downloadFailed = NSLocalizedString("aichat.download.failed", value: "Download failed", comment: "Download failed message")

}
#endif
