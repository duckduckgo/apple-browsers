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

    /// TranslateKit blocks and isn't thread-safe, so every call, setup included, goes through this queue.
    private let queue = DispatchQueue(label: "com.duckduckgo.webPageTranslation.languageDetection", qos: .userInitiated)
    /// Set up on first use, so launch never waits on TranslateKit; nil if setup failed, and it isn't retried.
    private lazy var translateKit: TranslateKit? = {
        do {
            return try TranslateKit()
        } catch {
            Logger.webPageTranslation.error("TranslateKit setup failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }()

    public init() {}

    /// The page's language when CLD2 is reliable, else nil.
    public func detectLanguage(of text: String) async -> String? {
        await withCheckedContinuation { continuation in
            queue.async {
                guard let translateKit = self.translateKit else {
                    continuation.resume(returning: nil)
                    return
                }
                do {
                    let result = try translateKit.detectLanguage(text)
                    continuation.resume(returning: result.isReliable ? result.language : nil)
                } catch {
                    Logger.webPageTranslation.error("Language detection failed: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
