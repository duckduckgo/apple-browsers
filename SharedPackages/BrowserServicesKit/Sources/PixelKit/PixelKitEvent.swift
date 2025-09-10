//
//  PixelKitEvent.swift
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

/// An event that can be fired using PixelKit.
public protocol PixelKitEvent {
    var name: String { get }
    var parameters: [String: String]? { get }
    /// Automatically implemented by the below extension using reflection, please implement the error, if needed as enum parameter
    var error: NSError? { get }
}

/// Extract Error parameter from the PixelKitEvent, only one error is supported, if multiple errors are found we assert
public extension PixelKitEvent {

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
                        assertionFailure("Multiple errors found in PixelKitEvent, only one error is supported")
                        return resultError
                    }
                    resultError = error
                }
            }
        }
        return resultError
    }
}
