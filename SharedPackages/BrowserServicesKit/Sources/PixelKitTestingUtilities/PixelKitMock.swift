//
//  PixelKitMock.swift
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

public final class PixelKitMock: PixelFiring {

    /// An array of fire calls, in order, that this mock expects
    ///
    public var expectedFireCalls: [ExpectedFireCall]

    /// The actual fire calls
    ///
    public private(set) var actualFireCalls = [ExpectedFireCall]()

    public init(expecting expectedFireCalls: [ExpectedFireCall] = []) {
        self.expectedFireCalls = expectedFireCalls
    }

    public func fire(_ event: PixelKitEvent,
                     frequency: PixelKit.Frequency,
                     withAdditionalParameters parameters: [String: String]?,
                     onComplete: @escaping PixelKit.CompletionBlock) {
        let fireCall = ExpectedFireCall(pixel: event, frequency: frequency, additionalParameters: parameters)
        actualFireCalls.append(fireCall)
        onComplete(true, nil)
    }

    public func verifyExpectations(file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(expectedFireCalls, actualFireCalls, file: file, line: line)
    }
}

public struct ExpectedFireCall: Equatable {
    public let pixel: PixelKitEvent
    public let frequency: PixelKit.Frequency
    public let additionalParameters: [String: String]?

    public init(pixel: PixelKitEvent, frequency: PixelKit.Frequency, additionalParameters: [String: String]? = nil) {
        self.pixel = pixel
        self.frequency = frequency
        self.additionalParameters = additionalParameters
    }

    public static func == (lhs: ExpectedFireCall, rhs: ExpectedFireCall) -> Bool {
        lhs.pixel.name == rhs.pixel.name
        && lhs.pixel.parameters == rhs.pixel.parameters
        && lhs.pixel.error == rhs.pixel.error
        && lhs.frequency == rhs.frequency
        && lhs.additionalParameters == rhs.additionalParameters
    }
}
