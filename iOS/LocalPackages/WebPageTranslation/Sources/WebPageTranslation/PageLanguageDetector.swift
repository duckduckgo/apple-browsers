//
//  PageLanguageDetector.swift
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

import Foundation
import os.log
import TranslateKit

/// Detects a page's language on the device with CLD2.
public final class PageLanguageDetector: @unchecked Sendable {

    /// TranslateKit blocks and isn't thread-safe, so every call goes through this queue.
    private let queue = DispatchQueue(label: "com.duckduckgo.webPageTranslation.languageDetection", qos: .userInitiated)
    private let translateKit: TranslateKit

    public init() throws {
        translateKit = try TranslateKit()
    }

    /// The page's language when CLD2 is reliable, else nil.
    public func detectLanguage(of text: String) async -> String? {
        await withCheckedContinuation { continuation in
            queue.async {
                do {
                    let result = try self.translateKit.detectLanguage(text)
                    continuation.resume(returning: result.isReliable ? result.language : nil)
                } catch {
                    Logger.webPageTranslation.error("Language detection failed: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
