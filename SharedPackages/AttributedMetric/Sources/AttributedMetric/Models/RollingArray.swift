//
//  RollingArray.swift
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

import Foundation

/// A rolling data structure that maintains exactly 7 values in a first-in-first-out manner.
///
/// `RollingArray` stores up to 7 values of any `Codable` and `Equatable` type. When a new value
/// is added via `append(_:)`, it removes the oldest value and adds the new one at the end, maintaining
/// a constant size of 7 internal slots.
///
/// ## Key Characteristics:
/// - **Fixed Size**: Always maintains exactly 7 internal slots
/// - **Rolling Behavior**: New values push out the oldest values automatically
/// - **Sparse Storage**: Slots can be empty (nil) or contain values
/// - **Read-Only Access**: Individual values can be read by index but not modified directly
/// - **Codable**: Can be serialized/deserialized for persistence
///
/// ## Usage Example:
/// ```swift
/// var rolling = RollingArray<Int>()
/// 
/// // Initially all slots are nil
/// rolling.count // 0
/// rolling.allValues // []
/// 
/// // Add some values
/// rolling.append(1)
/// rolling.append(2)
/// rolling.append(3)
/// 
/// rolling.count // 3
/// rolling.allValues // [1, 2, 3]
/// rolling[4] // 1 (first appended value)
/// rolling[5] // 2 (second appended value)
/// rolling[6] // 3 (third appended value)
/// rolling[0] // nil (empty slot)
/// 
/// // Fill all 7 slots
/// for i in 4...7 {
///     rolling.append(i)
/// }
/// rolling.allValues // [1, 2, 3, 4, 5, 6, 7]
/// 
/// // Adding more values rolls over
/// rolling.append(8)
/// rolling.allValues // [2, 3, 4, 5, 6, 7, 8] (1 was removed)
/// ```
///
/// ## Internal Structure:
/// Values are stored in an internal array where each slot can be either:
/// - `.nilValue`: Empty slot
/// - `.value(T)`: Contains a value of type T
///
/// The `allValues` property returns only the non-nil values, while `count` returns
/// the number of non-nil slots.
public class RollingArray<T: Codable & Equatable>: Codable {

    public var values: [InternalValue]

    public enum InternalValue: Codable, Equatable, CustomDebugStringConvertible {
        case unknown
        case value(T)

        public var debugDescription: String {
            switch self {
            case .unknown:
                "nil"
            case .value(let t):
                String(describing: t)
            }
        }
    }

    /// Creates a new `RollingArray` instance with all values initially set to `defaultValue`
    ///  The minimum capacity is 1, if set to 0 defaults to 1.
    public init(capacity: Int, defaultValue: InternalValue = .unknown) {
        self.values = Array(repeating: defaultValue, count: capacity)
    }

    /// Appends a new value to the rolling structure.
    ///
    /// This method removes the oldest value (at index 0) and adds the new value at the end.
    /// The rolling behaviour ensures that the structure always maintains exactly `capacity` slots.
    ///
    /// - Parameter value: The value to append to the rolling structure.
    ///
    /// ## Example:
    /// ```swift
    /// var rolling = RollingArray<String>(capacity: 7)
    /// rolling.append("Monday")
    /// rolling.append("Tuesday")
    /// // rolling[5] == "Monday", rolling[6] == "Tuesday"
    /// ```
    public func append(_ value: T) {
        if !values.isEmpty {
            values.removeFirst()
        }
        values.append(InternalValue.value(value))
    }

    /// Accesses the value at the specified index.
    ///
    /// Returns the value stored at the given index, or `nil` if the slot is empty or the index is invalid.
    /// Valid indices are 0 through 6, where 0 is the oldest slot and 6 is the newest slot.
    ///
    /// - Parameter index: The index of the slot to access (0-6).
    /// - Returns: The value at the specified index, or `nil` if empty or invalid.
    ///
    /// ## Example:
    /// ```swift
    /// let rolling = RollingArray<Int>()
    /// rolling.append(42)
    /// print(rolling[6]) // Optional(42)
    /// print(rolling[0]) // nil (empty slot)
    /// print(rolling[10]) // nil (invalid index)
    /// ```
    public subscript(index: Int) -> T? {
        get {
            guard index >= 0 && index < values.count else { return nil }
            switch values[index] {
            case .unknown:
                return nil
            case .value(let t):
                return t
            }
        }
        set {
            guard index >= 0 && index < values.count else { return }
            if let newValue = newValue {
                values[index] = .value(newValue)
            } else {
                values[index] = .unknown
            }
        }
    }

    /// Returns an array containing all non-nil values in the rolling structure.
    ///
    /// The returned array contains only the values that have been set, in the order they appear
    /// in the internal storage (oldest to newest). Empty slots are not included.
    ///
    /// ## Example:
    /// ```swift
    /// var rolling = RollingArray<String>()
    /// rolling.append("A")
    /// rolling.append("B")
    /// print(rolling.allValues) // ["A", "B"]
    /// ```
    public var allValues: [T] {
        return values.compactMap { value in
            switch value {
            case .unknown:
                return nil
            case .value(let t):
                return t
            }
        }
    }

    /// The number of non-`.unknown` values currently stored in the rolling structure.
    public var count: Int {
        return values.count(where: { $0 != .unknown })
    }

    /// The last value in the structure, nil if `.unknown`
    public var last: T? {
        guard let internalValue = values.last else {
            return nil
        }
        switch internalValue {
        case .unknown:
            return nil
        case .value(let value):
            return value
        }
    }

    /// The index of the last value, it can be the default value like `.unknown`
    /// Returns -1 if the capacity is 0
    public var lastIndex: Int {
        return values.count-1
    }
}

// MARK: - Convenience Type Aliases

public typealias RollingArrayBool = RollingArray<Bool>
public typealias RollingArrayInt = RollingArray<Int>
