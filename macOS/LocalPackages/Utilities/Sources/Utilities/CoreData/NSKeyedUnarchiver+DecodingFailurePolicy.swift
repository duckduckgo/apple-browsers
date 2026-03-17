//
//  NSKeyedUnarchiver+DecodingFailurePolicy.swift
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

extension NSKeyedUnarchiver {

    /// Unarchives an object with explicit `decodingFailurePolicy` and `requiresSecureCoding` parameters.
    ///
    /// Use `.setErrorAndReturn` for `decodingFailurePolicy` to prevent ObjC `NSException`s from
    /// being raised. Swift's `try?` does not catch ObjC exceptions, so the standard
    /// `unarchivedObject(ofClass:from:)` class method can crash if the unarchiver encounters invalid data.
    public static func unarchivedObject<T: NSObject & NSSecureCoding>(
        ofClass cls: T.Type,
        from data: Data,
        requiresSecureCoding: Bool,
        decodingFailurePolicy: NSCoder.DecodingFailurePolicy
    ) throws -> T? {
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
        unarchiver.decodingFailurePolicy = decodingFailurePolicy
        unarchiver.requiresSecureCoding = requiresSecureCoding
        let object = unarchiver.decodeObject(of: cls, forKey: NSKeyedArchiveRootObjectKey)
        unarchiver.finishDecoding()
        return object
    }

}
