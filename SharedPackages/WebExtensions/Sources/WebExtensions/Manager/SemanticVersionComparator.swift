//
//  SemanticVersionComparator.swift
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

/// Compares semantic versions for web extension upgrade decisions.
///
/// This comparator handles version strings with numeric components separated by dots.
/// Non-numeric components (e.g., "beta", "alpha") are ignored during comparison.
///
/// Examples:
/// - "1.2.3" vs "1.2.4" → 1.2.4 is newer
/// - "1.0" vs "1.0.0" → equal (trailing zeros are implicit)
/// - "1.0.0-beta" vs "1.0.0" → equal (non-numeric suffixes are stripped)
@available(macOS 15.4, iOS 18.4, *)
public struct SemanticVersionComparator {

    public init() {}

    /// Returns true if `newVersion` is strictly greater than `oldVersion`.
    ///
    /// Version strings are split by "." and each component is parsed as an integer.
    /// Non-numeric components are treated as 0. Missing trailing components are treated as 0.
    ///
    /// - Parameters:
    ///   - newVersion: The potentially newer version string
    ///   - oldVersion: The currently installed version string
    /// - Returns: `true` if newVersion > oldVersion, `false` otherwise
    public func isVersion(_ newVersion: String, newerThan oldVersion: String) -> Bool {
        let newComponents = parseVersionComponents(newVersion)
        let oldComponents = parseVersionComponents(oldVersion)

        let maxLength = max(newComponents.count, oldComponents.count)
        for i in 0..<maxLength {
            let newPart = i < newComponents.count ? newComponents[i] : 0
            let oldPart = i < oldComponents.count ? oldComponents[i] : 0
            if newPart > oldPart { return true }
            if newPart < oldPart { return false }
        }
        return false
    }

    /// Determines if an extension should be upgraded based on version comparison.
    ///
    /// - Parameters:
    ///   - installedVersion: The currently installed version (nil if unknown)
    ///   - bundledVersion: The bundled version to potentially upgrade to (nil if unknown)
    /// - Returns: `true` if the bundled version should replace the installed version
    public func shouldUpgrade(installedVersion: String?, bundledVersion: String?) -> Bool {
        guard let bundledVersion else {
            return false
        }
        guard let installedVersion else {
            return true
        }
        return isVersion(bundledVersion, newerThan: installedVersion)
    }

    /// Parses a version string into an array of integer components.
    /// Non-numeric parts are parsed as 0.
    private func parseVersionComponents(_ version: String) -> [Int] {
        version.split(separator: ".").map { component in
            let numericPrefix = component.prefix { $0.isNumber }
            return Int(numericPrefix) ?? 0
        }
    }
}
