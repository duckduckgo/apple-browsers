//
//  AIChatConsumableDataHandling.swift
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

/// A protocol that defines a standard interface for handling consumable data.
/// Types conforming to this protocol can set, consume, and reset data of a specified type.
protocol AIChatConsumableDataHandling {
    /// The type of data that the conforming type will handle.
    associatedtype DataType

    /// Sets the data to be handled.
    ///
    /// - Parameter data: The data to be set.
    func setData(_ data: DataType)

    /// Consumes the current data and returns it.
    ///
    /// - Returns: The current data if available, otherwise `nil`.
    func consumeData() -> DataType?

    /// Resets the current data, clearing any stored value.
    func reset()
}

final class AIChatPromptHandler: AIChatConsumableDataHandling {
    typealias DataType = String
    static let shared = AIChatPromptHandler()

    private init() {}

    private var prompt: String?

    func setData(_ data: String) {
        self.prompt = data
    }

    func consumeData() -> String? {
        let currentPrompt = prompt
        reset()
        return currentPrompt
    }

    func reset() {
        self.prompt = nil
    }
}
