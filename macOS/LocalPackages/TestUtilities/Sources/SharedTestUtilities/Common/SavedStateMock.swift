//
//  SavedStateMock.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

import AppKitExtensions
import Foundation

@objc
public final class SavedStateMock: NSObject {
    private enum NSSecureCodingKeys {
        static let key1 = "key1"
        static let key2 = "key2"
    }
    public static var supportsSecureCoding = true

    public var val1: String?
    public var val2: Int?

    public override init() {
    }

    public func encode(with coder: NSCoder) {
        val1.map(coder.encode(forKey: NSSecureCodingKeys.key1))
        val2.map(coder.encode(forKey: NSSecureCodingKeys.key2))
    }

    public func restoreState(from coder: NSCoder) throws {
        val1 = coder.decodeIfPresent(at: NSSecureCodingKeys.key1)
        val2 = coder.decodeIfPresent(at: NSSecureCodingKeys.key2)
    }
}
