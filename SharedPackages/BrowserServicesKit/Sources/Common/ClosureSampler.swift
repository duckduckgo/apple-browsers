//
//  ClosureSampler.swift
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
import os.log

/// A utility class that samples closures based on a percentage
public final class ClosureSampler {
    private let logger = Logger(subsystem: "com.duckduckgo.browser", category: "ClosureSampler")

    public let percentage: Int

    public init(percentage: Int) {
        self.percentage = max(1, min(100, percentage))
    }

    @discardableResult
    public func sample<T>(_ closure: () -> T) -> T? {
        guard shouldSample() else {
            logger.debug("Closure skipped due to sampling (percentage: \(self.percentage)%)")
            return nil
        }

        logger.debug("Closure executed due to sampling (percentage: \(self.percentage)%)")
        return closure()
    }

    @discardableResult
    public func sample(_ closure: () -> Void) -> Bool {
        guard shouldSample() else {
            logger.debug("Closure skipped due to sampling (percentage: \(self.percentage)%)")
            return false
        }

        logger.debug("Closure executed due to sampling (percentage: \(self.percentage)%)")
        closure()
        return true
    }

    private func shouldSample() -> Bool {
        let randomValue = Int.random(in: 1...100)
        return randomValue <= percentage
    }
}
