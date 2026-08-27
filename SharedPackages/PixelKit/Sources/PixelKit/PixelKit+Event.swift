//
//  PixelKit+Event.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import Common
import FoundationExtensions

public enum PixelKitStandardParameter {
    case pixelSource
}

extension PixelKit {

    /// An event that can be fired using PixelKit.
    public protocol Event {
        var name: String { get }
        var standardParameters: [PixelKitStandardParameter]? { get }
        var parameters: [String: String]? { get }
        /// Automatically implemented by the below extension using reflection, please implement the error, if needed as enum parameter
        var error: NSError? { get }
        /// Where the iOS platform marker goes. Defaults to `.standard`.
        var platformSuffixPolicy: PixelKitPlatformSuffixPolicy { get }
        /// What precedes `name`. Defaults to `.platformDefault`.
        var namePrefix: PixelKitNamePrefix { get }
    }
}

public extension PixelKit.Event {

    var platformSuffixPolicy: PixelKitPlatformSuffixPolicy { .standard }

    var namePrefix: PixelKitNamePrefix { .platformDefault }

    /// Returns this event with `prefix` in front of its name, overriding `namePrefix`.
    ///
    /// For shared packages whose prefix is chosen by the host app rather than by the pixel, e.g.
    /// `pixelKit.fire(event.prefixed(platform.pixelNamePrefix))`.
    func prefixed(_ prefix: String) -> PixelKit.Event {
        PixelKitPrefixedEvent(wrapped: self, namePrefix: .custom(prefix))
    }
}

/// See `PixelKit.Event.prefixed(_:)`.
struct PixelKitPrefixedEvent: PixelKit.Event {
    let wrapped: PixelKit.Event
    let namePrefix: PixelKitNamePrefix

    var name: String { wrapped.name }
    var parameters: [String: String]? { wrapped.parameters }
    var standardParameters: [PixelKitStandardParameter]? { wrapped.standardParameters }
    /// Declared so the reflection-based default inspects the wrapped event, not this wrapper.
    var error: NSError? { wrapped.error }
    var platformSuffixPolicy: PixelKitPlatformSuffixPolicy { wrapped.platformSuffixPolicy }
}

/// Extract Error parameter from the PixelKit.Event, only one error is supported, if multiple errors are found we assert
public extension PixelKit.Event {

    var error: NSError? {
        let mirror = Mirror(reflecting: self)
        var resultError: NSError?
        for child in mirror.children {
            let associated = child.value
            // Check if the associated value is directly an Error
            if let error = associated as? NSError {
                return error
            }

            // If it's a tuple (multiple associated values), check each one
            let associatedMirror = Mirror(reflecting: associated)
            for child in associatedMirror.children {
                if let error = child.value as? NSError {
                    guard resultError == nil else {
                        assertionFailure("Multiple errors found in PixelKit.Event, only one error is supported")
                        return resultError
                    }
                    resultError = error
                }
            }
        }
        return resultError
    }
}
