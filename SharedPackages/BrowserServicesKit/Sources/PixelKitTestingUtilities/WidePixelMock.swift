//
//  WidePixelMock.swift
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
import PixelKit
import XCTest

public final class WidePixelMock: WidePixelManaging {
    public private(set) var started: [Any] = []
    public private(set) var updates: [Any] = []
    public private(set) var completions: [(Any, WidePixelStatus)] = []

    public init() {}

    public func startFlow<T>(_ data: T) where T: WidePixelData {
        started.append(data)
    }

    public func updateFlow<T>(_ data: T) where T: WidePixelData {
        updates.append(data)
    }

    public func completeFlow<T>(_ data: T, status: WidePixelStatus, onComplete: @escaping PixelKit.CompletionBlock) where T: WidePixelData {
        completions.append((data, status))
        onComplete(true, nil)
    }
}
