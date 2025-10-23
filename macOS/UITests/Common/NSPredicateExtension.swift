//
//  NSPredicateExtension.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import XCTest
import ObjectiveC

extension NSPredicate {

    private class ComputedKeyPathHelper: NSObject {
        @objc var value: Any?
    }

    /// Helper to extract value from element using keypath, preferring KVC when available
    private static func getValue<T>(from element: Any?, keyPath: AnyKeyPath, as type: T.Type) -> T? {
        // First try KVC if available (faster and more reliable for XCUIElement properties)
        if let obj = element as? NSObject,
           let key = keyPath._kvcKeyPathString {
            return obj.value(forKey: key) as? T
        }
        // Fall back to keypath subscript for computed properties
        return element?[keyPath: keyPath] as? T
    }

    // MARK: - KeyPath-based Static Constructors

    static func keyPath(_ keyPath: PartialKeyPath<XCUIElement>, equalTo value: CVarArg) -> NSPredicate {
        self.keyPath(keyPath as AnyKeyPath, equalTo: value)
    }

    /// Creates a predicate that checks if a KeyPath property equals a specific value
    /// - Parameters:
    ///   - keyPath: The KeyPath to the property to check
    ///   - value: The value to compare against (supports String, Int, Double, Float, Bool)
    /// - Returns: NSPredicate for equality comparison with proper format specifier
    static func keyPath(_ keyPath: AnyKeyPath, equalTo value: CVarArg) -> NSPredicate {
        guard let key = keyPath._kvcKeyPathString else {
            let helper = ComputedKeyPathHelper()
            let keyDesc = keyPath._kvcKeyPathString ?? String(describing: keyPath)
            return NSPredicate(description: "\(keyDesc) == \(value)") { element, _ in
                helper.value = getValue(from: element, keyPath: keyPath, as: Any.self)
                return NSPredicate.keyPath(\ComputedKeyPathHelper.value, equalTo: value).evaluate(with: helper)
            }
        }

        let formatSpecifier: String
        switch type(of: value) {
        case is String.Type:
            formatSpecifier = "%@"
        case is Int.Type, is Int32.Type:
            formatSpecifier = "%d"
        case is Int64.Type:
            formatSpecifier = "%ld"
        case is UInt.Type, is UInt32.Type:
            formatSpecifier = "%u"
        case is UInt64.Type:
            formatSpecifier = "%llu"
        case is Double.Type, is Float.Type:
            formatSpecifier = "%f"
        case is Bool.Type:
            let boolValue = value as! Bool
            return NSPredicate(format: "%K == %@", key, NSNumber(value: boolValue))
        default:
            formatSpecifier = "%@"
        }
        return NSPredicate(format: "%K == \(formatSpecifier)", key, value)
    }

    // MARK: - Numeric Comparisons

    static func keyPath<Value: CVarArg & Comparable>(_ keyPath: PartialKeyPath<XCUIElement>, in range: ClosedRange<Value>) -> NSPredicate {
        return self.keyPath(keyPath as AnyKeyPath, in: range)
    }

    /// Creates a predicate that checks if a KeyPath numeric property is within a range
    /// - Parameters:
    ///   - keyPath: The KeyPath to the numeric property to check
    ///   - range: The range to check against (supports ClosedRange, Range, PartialRangeFrom, PartialRangeThrough, PartialRangeUpTo)
    /// - Returns: NSPredicate for range comparison with proper format specifier
    static func keyPath<Value: CVarArg & Comparable>(_ keyPath: AnyKeyPath, in range: ClosedRange<Value>) -> NSPredicate {
        guard let key = keyPath._kvcKeyPathString else {
            let helper = ComputedKeyPathHelper()
            let keyDesc = keyPath._kvcKeyPathString ?? String(describing: keyPath)
            return NSPredicate(description: "\(keyDesc) BETWEEN {\(range.lowerBound), \(range.upperBound)}") { element, _ in
                helper.value = getValue(from: element, keyPath: keyPath, as: Any.self)
                return NSPredicate.keyPath(\ComputedKeyPathHelper.value, in: range).evaluate(with: helper)
            }
        }

        let lowerBound = range.lowerBound
        let upperBound = range.upperBound

        switch Value.self {
        case is Int.Type, is Int?.Type, is Int32.Type, is Int32?.Type:
            return NSPredicate(format: "%K BETWEEN {%d, %d}", key, lowerBound, upperBound)
        case is Int64.Type, is Int64?.Type:
            return NSPredicate(format: "%K BETWEEN {%ld, %ld}", key, lowerBound, upperBound)
        case is UInt.Type, is UInt?.Type, is UInt32.Type, is UInt32?.Type:
            return NSPredicate(format: "%K BETWEEN {%u, %u}", key, lowerBound, upperBound)
        case is UInt64.Type, is UInt64?.Type:
            return NSPredicate(format: "%K BETWEEN {%llu, %llu}", key, lowerBound, upperBound)
        case is Double.Type, is Double?.Type, is Float.Type, is Float?.Type:
            return NSPredicate(format: "%K BETWEEN {%f, %f}", key, lowerBound, upperBound)
        default:
            return NSPredicate(format: "%K BETWEEN {%@, %@}", key, lowerBound, upperBound)
        }
    }

    static func keyPath<Value: CVarArg & Comparable>(_ keyPath: PartialKeyPath<XCUIElement>, in range: Range<Value>) -> NSPredicate {
        return self.keyPath(keyPath as AnyKeyPath, in: range)
    }

    /// Creates a predicate that checks if a KeyPath numeric property is within a half-open range
    static func keyPath<Value: CVarArg & Comparable>(_ keyPath: AnyKeyPath, in range: Range<Value>) -> NSPredicate {
        guard let key = keyPath._kvcKeyPathString else {
            let helper = ComputedKeyPathHelper()
            let keyDesc = keyPath._kvcKeyPathString ?? String(describing: keyPath)
            return NSPredicate(description: "\(keyDesc) >= \(range.lowerBound) AND \(keyDesc) < \(range.upperBound)") { element, _ in
                helper.value = getValue(from: element, keyPath: keyPath, as: Any.self)
                return NSPredicate.keyPath(\ComputedKeyPathHelper.value, in: range).evaluate(with: helper)
            }
        }

        let lowerBound = range.lowerBound
        let upperBound = range.upperBound

        switch Value.self {
        case is Int.Type, is Int?.Type, is Int32.Type, is Int32?.Type:
            return NSPredicate(format: "%K >= %d AND %K < %d", key, lowerBound, key, upperBound)
        case is Int64.Type, is Int64?.Type:
            return NSPredicate(format: "%K >= %ld AND %K < %ld", key, lowerBound, key, upperBound)
        case is UInt.Type, is UInt?.Type, is UInt32.Type, is UInt32?.Type:
            return NSPredicate(format: "%K >= %u AND %K < %u", key, lowerBound, key, upperBound)
        case is UInt64.Type, is UInt64?.Type:
            return NSPredicate(format: "%K >= %llu AND %K < %llu", key, lowerBound, key, upperBound)
        case is Double.Type, is Double?.Type, is Float.Type, is Float?.Type:
            return NSPredicate(format: "%K >= %f AND %K < %f", key, lowerBound, key, upperBound)
        default:
            return NSPredicate(format: "%K >= %@ AND %K < %@", key, lowerBound, key, upperBound)
        }
    }

    static func keyPath<Value: CVarArg & Comparable>(_ keyPath: PartialKeyPath<XCUIElement>, in range: PartialRangeFrom<Value>) -> NSPredicate {
        return self.keyPath(keyPath as AnyKeyPath, in: range)
    }

    /// Creates a predicate that checks if a KeyPath numeric property is greater than or equal to a value
    static func keyPath<Value: CVarArg & Comparable>(_ keyPath: AnyKeyPath, in range: PartialRangeFrom<Value>) -> NSPredicate {
        guard let key = keyPath._kvcKeyPathString else {
            let helper = ComputedKeyPathHelper()
            let keyDesc = keyPath._kvcKeyPathString ?? String(describing: keyPath)
            return NSPredicate(description: "\(keyDesc) >= \(range.lowerBound)") { element, _ in
                helper.value = getValue(from: element, keyPath: keyPath, as: Any.self)
                return NSPredicate.keyPath(\ComputedKeyPathHelper.value, in: range).evaluate(with: helper)
            }
        }

        let lowerBound = range.lowerBound

        switch type(of: lowerBound) {
        case is Int.Type, is Int?.Type, is Int32.Type, is Int32?.Type:
            return NSPredicate(format: "%K >= %d", key, lowerBound)
        case is Int64.Type, is Int64?.Type:
            return NSPredicate(format: "%K >= %ld", key, lowerBound)
        case is UInt.Type, is UInt?.Type, is UInt32.Type, is UInt32?.Type:
            return NSPredicate(format: "%K >= %u", key, lowerBound)
        case is UInt64.Type, is UInt64?.Type:
            return NSPredicate(format: "%K >= %llu", key, lowerBound)
        case is Double.Type, is Double?.Type, is Float.Type, is Float?.Type:
            return NSPredicate(format: "%K >= %f", key, lowerBound)
        default:
            return NSPredicate(format: "%K >= %@", key, lowerBound)
        }
    }

    static func keyPath<Value: CVarArg & Comparable>(_ keyPath: PartialKeyPath<XCUIElement>, in range: PartialRangeUpTo<Value>) -> NSPredicate {
        return self.keyPath(keyPath as AnyKeyPath, in: range)
    }

    /// Creates a predicate that checks if a KeyPath numeric property is greater than a value
    static func keyPath<Value: CVarArg & Comparable>(_ keyPath: AnyKeyPath, in range: PartialRangeUpTo<Value>) -> NSPredicate {
        guard let key = keyPath._kvcKeyPathString else {
            let helper = ComputedKeyPathHelper()
            let keyDesc = keyPath._kvcKeyPathString ?? String(describing: keyPath)
            return NSPredicate(description: "\(keyDesc) < \(range.upperBound)") { element, _ in
                helper.value = getValue(from: element, keyPath: keyPath, as: Any.self)
                return NSPredicate.keyPath(\ComputedKeyPathHelper.value, in: range).evaluate(with: helper)
            }
        }

        let upperBound = range.upperBound

        switch type(of: upperBound) {
        case is Int.Type, is Int?.Type, is Int32.Type, is Int32?.Type:
            return NSPredicate(format: "%K < %d", key, upperBound)
        case is Int64.Type, is Int64?.Type:
            return NSPredicate(format: "%K < %ld", key, upperBound)
        case is UInt.Type, is UInt?.Type, is UInt32.Type, is UInt32?.Type:
            return NSPredicate(format: "%K < %u", key, upperBound)
        case is UInt64.Type, is UInt64?.Type:
            return NSPredicate(format: "%K < %llu", key, upperBound)
        case is Double.Type, is Double?.Type, is Float.Type, is Float?.Type:
            return NSPredicate(format: "%K < %f", key, upperBound)
        default:
            return NSPredicate(format: "%K < %@", key, upperBound)
        }
    }

    static func keyPath<Value: CVarArg & Comparable>(_ keyPath: PartialKeyPath<XCUIElement>, in range: PartialRangeThrough<Value>) -> NSPredicate {
        return self.keyPath(keyPath as AnyKeyPath, in: range)
    }

    /// Creates a predicate that checks if a KeyPath numeric property is less than or equal to a value
    static func keyPath<Value: CVarArg & Comparable>(_ keyPath: AnyKeyPath, in range: PartialRangeThrough<Value>) -> NSPredicate {
        guard let key = keyPath._kvcKeyPathString else {
            let helper = ComputedKeyPathHelper()
            let keyDesc = keyPath._kvcKeyPathString ?? String(describing: keyPath)
            return NSPredicate(description: "\(keyDesc) <= \(range.upperBound)") { element, _ in
                helper.value = getValue(from: element, keyPath: keyPath, as: Any.self)
                return NSPredicate.keyPath(\ComputedKeyPathHelper.value, in: range).evaluate(with: helper)
            }
        }

        let upperBound = range.upperBound

        switch type(of: upperBound) {
        case is Int.Type, is Int?.Type, is Int32.Type, is Int32?.Type:
            return NSPredicate(format: "%K <= %d", key, upperBound)
        case is Int64.Type, is Int64?.Type:
            return NSPredicate(format: "%K <= %ld", key, upperBound)
        case is UInt.Type, is UInt?.Type, is UInt32.Type, is UInt32?.Type:
            return NSPredicate(format: "%K <= %u", key, upperBound)
        case is UInt64.Type, is UInt64?.Type:
            return NSPredicate(format: "%K <= %llu", key, upperBound)
        case is Double.Type, is Double?.Type, is Float.Type, is Float?.Type:
            return NSPredicate(format: "%K <= %f", key, upperBound)
        default:
            return NSPredicate(format: "%K <= %@", key, upperBound)
        }
    }

    // MARK: - Collection Operations

    static func keyPath<Value: CVarArg, Collection: Swift.Collection>(_ keyPath: PartialKeyPath<XCUIElement>, in values: Collection) -> NSPredicate where Collection.Element == Value {
        return self.keyPath(keyPath as AnyKeyPath, in: values)
    }

    /// Creates a predicate that checks if a KeyPath property is in a collection of values
    static func keyPath<Value: CVarArg, Collection: Swift.Collection>(_ keyPath: AnyKeyPath, in values: Collection) -> NSPredicate where Collection.Element == Value {
        guard let key = keyPath._kvcKeyPathString else {
            let helper = ComputedKeyPathHelper()
            let keyDesc = keyPath._kvcKeyPathString ?? String(describing: keyPath)
            let valuesArray = Array(values)
            return NSPredicate(description: "\(keyDesc) IN \(valuesArray)") { element, _ in
                helper.value = getValue(from: element, keyPath: keyPath, as: Any.self)
                return NSPredicate.keyPath(\ComputedKeyPathHelper.value, in: values).evaluate(with: helper)
            }
        }
        return NSPredicate(format: "%K IN %@", key, Array(values))
    }

    static func keyPath(_ keyPath: PartialKeyPath<XCUIElement>, contains substring: String) -> NSPredicate {
        return self.keyPath(keyPath as AnyKeyPath, contains: substring)
    }

    /// Creates a predicate that checks if a KeyPath string property contains a substring
    /// - Parameters:
    ///   - keyPath: The KeyPath to the string property to check
    ///   - substring: The substring to search for
    /// - Returns: NSPredicate for contains comparison using localizedStandardContains
    static func keyPath(_ keyPath: AnyKeyPath, contains substring: String) -> NSPredicate {
        let keyDesc = keyPath._kvcKeyPathString ?? String(describing: keyPath)
        return NSPredicate(description: "\(keyDesc) CONTAINS[c] \"\(substring)\"") { element, _ in
            guard let stringValue = getValue(from: element, keyPath: keyPath, as: String.self) else { return false }
            return stringValue.localizedStandardContains(substring)
        }
    }

    static func keyPath(_ keyPath: PartialKeyPath<XCUIElement>, like pattern: String) -> NSPredicate {
        return self.keyPath(keyPath as AnyKeyPath, like: pattern)
    }

    /// Creates a predicate that checks if a KeyPath string property matches a pattern using LIKE
    /// - Parameters:
    ///   - keyPath: The KeyPath to the string property to check
    ///   - pattern: The pattern to match (supports * and ? wildcards)
    /// - Returns: NSPredicate for LIKE pattern matching
    static func keyPath(_ keyPath: AnyKeyPath, like pattern: String) -> NSPredicate {
        let keyDesc = keyPath._kvcKeyPathString ?? String(describing: keyPath)
        return NSPredicate(description: "\(keyDesc) LIKE \"\(pattern)\"") { element, _ in
            guard let stringValue = getValue(from: element, keyPath: keyPath, as: String.self) else { return false }
            // Escape regex special chars, then replace LIKE wildcards with regex equivalents
            let escaped = NSRegularExpression.escapedPattern(for: pattern)
            let regexPattern = escaped
                .replacingOccurrences(of: "\\?", with: ".")
                .replacingOccurrences(of: "\\*", with: ".*")
            return stringValue.range(of: "^\(regexPattern)$", options: .regularExpression) != nil
        }
    }

    static func keyPath(_ keyPath: PartialKeyPath<XCUIElement>, beginsWith prefix: String) -> NSPredicate {
        return self.keyPath(keyPath as AnyKeyPath, beginsWith: prefix)
    }

    /// Creates a predicate that checks if a KeyPath string property begins with a prefix
    /// - Parameters:
    ///   - keyPath: The KeyPath to the string property to check
    ///   - prefix: The prefix to check for
    /// - Returns: NSPredicate for BEGINSWITH comparison
    static func keyPath(_ keyPath: AnyKeyPath, beginsWith prefix: String) -> NSPredicate {
        let keyDesc = keyPath._kvcKeyPathString ?? String(describing: keyPath)
        return NSPredicate(description: "\(keyDesc) BEGINSWITH \"\(prefix)\"") { element, _ in
            guard let stringValue = getValue(from: element, keyPath: keyPath, as: String.self) else { return false }
            return stringValue.hasPrefix(prefix)
        }
    }

    static func keyPath(_ keyPath: PartialKeyPath<XCUIElement>, endsWith suffix: String) -> NSPredicate {
        return self.keyPath(keyPath as AnyKeyPath, endsWith: suffix)
    }

    /// Creates a predicate that checks if a KeyPath string property ends with a suffix
    /// - Parameters:
    ///   - keyPath: The KeyPath to the string property to check
    ///   - suffix: The suffix to check for
    /// - Returns: NSPredicate for ENDSWITH comparison
    static func keyPath(_ keyPath: AnyKeyPath, endsWith suffix: String) -> NSPredicate {
        let keyDesc = keyPath._kvcKeyPathString ?? String(describing: keyPath)
        return NSPredicate(description: "\(keyDesc) ENDSWITH \"\(suffix)\"") { element, _ in
            guard let stringValue = getValue(from: element, keyPath: keyPath, as: String.self) else { return false }
            return stringValue.hasSuffix(suffix)
        }
    }

    static func keyPath(_ keyPath: PartialKeyPath<XCUIElement>, matchingRegex pattern: String) -> NSPredicate {
        return self.keyPath(keyPath as AnyKeyPath, matchingRegex: pattern)
    }

    /// Creates a predicate that checks if a KeyPath string property matches a regular expression
    /// - Parameters:
    ///   - keyPath: The KeyPath to the string property to check
    ///   - pattern: The regular expression pattern to match
    /// - Returns: NSPredicate for MATCHES comparison with case-insensitive flag
    static func keyPath(_ keyPath: AnyKeyPath, matchingRegex pattern: String) -> NSPredicate {
        let keyDesc = keyPath._kvcKeyPathString ?? String(describing: keyPath)
        return NSPredicate(description: "\(keyDesc) MATCHES[c] \"\(pattern)\"") { element, _ in
            guard let stringValue = getValue(from: element, keyPath: keyPath, as: String.self) else { return false }
            return stringValue.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }

    // MARK: - Compound Predicate Helpers

    /// Creates an AND compound predicate from multiple predicates (variadic)
    /// - Parameter predicates: Variable number of predicates to combine with AND
    /// - Returns: NSCompoundPredicate with AND type
    func and(_ predicates: NSPredicate...) -> NSPredicate {
        return NSCompoundPredicate(andPredicateWithSubpredicates: [self] + predicates)
    }

    /// Creates an AND compound predicate from multiple predicates (variadic)
    /// - Parameter predicates: Variable number of predicates to combine with AND
    /// - Returns: NSCompoundPredicate with AND type
    static func and(_ predicates: NSPredicate...) -> NSPredicate {
        return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    }

    /// Creates an AND compound predicate from an array of predicates
    /// - Parameter predicates: Array of predicates to combine with AND
    /// - Returns: NSCompoundPredicate with AND type
    static func and(_ predicates: [NSPredicate]) -> NSPredicate {
        return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    }

    /// Creates an OR compound predicate from multiple predicates (variadic)
    /// - Parameter predicates: Variable number of predicates to combine with OR
    /// - Returns: NSCompoundPredicate with OR type
    func or(_ predicates: NSPredicate...) -> NSPredicate {
        return NSCompoundPredicate(orPredicateWithSubpredicates: [self] + predicates)
    }

    /// Creates an OR compound predicate from multiple predicates (variadic)
    /// - Parameter predicates: Variable number of predicates to combine with OR
    /// - Returns: NSCompoundPredicate with OR type
    static func or(_ predicates: NSPredicate...) -> NSPredicate {
        return NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
    }

    /// Creates an OR compound predicate from an array of predicates
    /// - Parameter predicates: Array of predicates to combine with OR
    /// - Returns: NSCompoundPredicate with OR type
    static func or(_ predicates: [NSPredicate]) -> NSPredicate {
        return NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
    }

    static func not(_ predicate: NSPredicate) -> NSPredicate {
        return NSCompoundPredicate(notPredicateWithSubpredicate: predicate)
    }

    /// Creates a NOT predicate that inverts this predicate
    /// - Returns: NSCompoundPredicate with NOT type
    var inverted: NSPredicate {
        return NSCompoundPredicate(notPredicateWithSubpredicate: self)
    }

}

extension NSPredicate {

    private static let customDescriptionKey = UnsafeRawPointer(bitPattern: "customDescriptionKey".hashValue)!
    private var customDescription: String? {
        get {
            objc_getAssociatedObject(self, Self.customDescriptionKey) as? String
        }
        set {
            objc_setAssociatedObject(self, Self.customDescriptionKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    convenience init(description: String, block: @escaping (Any?, [String: Any]?) -> Bool) {
        self.init(block: block)
        self.customDescription = description
        _=Self.swizzlePredicateFormatOnce
    }

    private static let swizzlePredicateFormatOnce: Void = {
        let originalSelector = #selector(getter: predicateFormat)
        let swizzledSelector = #selector(getter: swizzled_predicateFormat)

        guard let originalMethod = class_getInstanceMethod(NSPredicate.self, originalSelector),
              let swizzledMethod = class_getInstanceMethod(NSPredicate.self, swizzledSelector) else {
            return
        }

        method_exchangeImplementations(originalMethod, swizzledMethod)
    }()

    @objc private dynamic var swizzled_predicateFormat: String {
        if let customDesc = self.customDescription {
            return customDesc
        }
        return self.swizzled_predicateFormat
    }

}
