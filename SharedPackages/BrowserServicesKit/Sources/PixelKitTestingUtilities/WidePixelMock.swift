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
    public var started: [WidePixelData] = []
    public var updates: [WidePixelData] = []
    public var completions: [(WidePixelData, WidePixelStatus)] = []
    public var discarded: [WidePixelData] = []

    public init() {}

    public func startFlow<T: WidePixelData>(_ data: T) {
        started.append(data)
    }

    public func updateFlow<T: WidePixelData>(_ data: T) {
        updates.append(data)
    }

    public func completeFlow<T: WidePixelData>(_ data: T, status: WidePixelStatus, onComplete: @escaping PixelKit.CompletionBlock) {
        completions.append((data, status))
        onComplete(true, nil)
    }

    public func completeFlow<T: WidePixelData>(_ data: T, status: WidePixelStatus) async throws -> Bool {
        completions.append((data, status))
        return true
    }

    public func discardFlow<T: WidePixelData>(_ data: T) {
        discarded.append(data)
    }

    public func getAllFlowData<T: WidePixelData>(_ type: T.Type) -> [T] {
        return started.compactMap { $0 as? T }
    }
}
