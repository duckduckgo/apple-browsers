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
        /// Where the `_ios_phone` / `_ios_tablet` marker goes in this pixel's name.
        ///
        /// Defaults to `.standard`, which is what every new pixel wants. Only override it to freeze
        /// a name that shipped before the marker was applied consistently.
        var platformSuffixPolicy: PixelKitPlatformSuffixPolicy { get }
        /// What goes in front of `name`.
        ///
        /// Defaults to `.platformDefault`. Together with `platformSuffixPolicy` this is the whole of
        /// a pixel's naming identity, and it lives here rather than on `Options` so that every call
        /// site firing this event necessarily agrees on the name.
        var namePrefix: PixelKitNamePrefix { get }
    }
}

public extension PixelKit.Event {

    /// The correct convention, so a new pixel gets it without opting in. See
    /// `PixelKitPlatformSuffixPolicy` for the legacy cases and why they exist.
    var platformSuffixPolicy: PixelKitPlatformSuffixPolicy { .standard }

    /// The host platform's convention, which is what a pixel wants unless its name is already
    /// complete. See `PixelKitNamePrefix`.
    var namePrefix: PixelKitNamePrefix { .platformDefault }

    /// This event, wearing an explicit name prefix.
    ///
    /// For shared packages whose prefix is picked by the host platform rather than by the pixel:
    /// `DataBrokerProtectionSharedPixelsHandler` and `OnboardingPixelReporter` each take a
    /// `Platform` at construction and turn it into `m_mac_` or `m_ios_`. That is a per-process fact
    /// the event type cannot know, but it is still naming identity, so it belongs on an event value
    /// rather than in the `Options` of every individual fire call.
    func prefixed(_ prefix: String) -> PixelKit.Event {
        PixelKitPrefixedEvent(wrapped: self, namePrefix: .custom(prefix))
    }
}

/// An event wearing a different name prefix. See `PixelKit.Event.prefixed(_:)`.
struct PixelKitPrefixedEvent: PixelKit.Event {
    let wrapped: PixelKit.Event
    let namePrefix: PixelKitNamePrefix

    var name: String { wrapped.name }
    var parameters: [String: String]? { wrapped.parameters }
    var standardParameters: [PixelKitStandardParameter]? { wrapped.standardParameters }
    /// Forwarded explicitly: the reflection-based default would inspect this wrapper rather than the
    /// event it wraps.
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
