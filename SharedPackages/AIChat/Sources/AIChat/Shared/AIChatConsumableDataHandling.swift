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
public protocol AIChatConsumableDataHandling {
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

/// Handles prompt data for AI chat interactions.
public final class AIChatPromptHandler: AIChatConsumableDataHandling {
    public typealias DataType = String
    private var data: DataType?

    public static let shared = AIChatPromptHandler()

    private init() {}

    public func setData(_ data: DataType) {
        self.data = data
    }

    public func consumeData() -> DataType? {
        let currentData = data
        reset()
        return currentData
    }

    public func reset() {
        self.data = nil
    }
}

/// Handles payload data for AI chat interactions, typically set by the SERP.
public final class AIChatPayloadHandler: AIChatConsumableDataHandling {
    public typealias DataType = AIChatPayload
    private var data: DataType?

    public init() {}

    public func setData(_ data: DataType) {
        self.data = data
    }

    public func consumeData() -> DataType? {
        let currentData = data
        reset()
        return currentData
    }

    public func reset() {
        self.data = nil
    }
}

/// The payload is configured by the SERP to facilitate data transfer to duck.ai.
/// For instance, when a user searches for "bread recipe" and clicks the chat button, the SERP sets this payload.
/// The payload is then consumed when duck.ai is initialized, allowing for seamless data integration.
public typealias AIChatPayload = [String: Any]
