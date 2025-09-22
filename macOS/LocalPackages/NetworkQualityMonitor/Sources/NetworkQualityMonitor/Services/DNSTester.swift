//
//  DNSTester.swift
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

/// Service responsible for DNS testing
public final class DNSTester: DNSTesting {

    // MARK: - Constants

    private enum Constants {
        static let progressMessage = "Testing DNS resolution..."
        static let measurementDelay: UInt64 = 50_000_000  // 50ms between DNS queries
    }

    public func performTest(configuration: TestConfiguration,
                            progressCallback: ((String) -> Void)? = nil) async throws -> DNSResult {
        progressCallback?(Constants.progressMessage)

        var resolutionTimes: [Double] = []
        var failures = 0
        let totalTests = configuration.dnsTestDomains.count

        for domain in configuration.dnsTestDomains {
            // Use default priority to match CFHostStartInfoResolution's internal thread priority
            let result = await Task(priority: .medium) {
                let startTime = CFAbsoluteTimeGetCurrent()
                let host = CFHostCreateWithName(nil, domain as CFString).takeRetainedValue()

                let resolved = CFHostStartInfoResolution(host, .addresses, nil)
                let endTime = CFAbsoluteTimeGetCurrent()
                let resolutionTime = (endTime - startTime) * 1000 // Convert to ms

                return (resolved: resolved, time: resolutionTime)
            }.value

            if result.resolved {
                resolutionTimes.append(result.time)
            } else {
                failures += 1
            }

            // Small delay between DNS queries
            try? await Task.sleep(nanoseconds: Constants.measurementDelay)
        }

        guard !resolutionTimes.isEmpty else {
            throw NetworkError.allTestsFailed
        }

        let medianTime = NetworkTestConstants.median(of: resolutionTimes) ?? 0
        let failureRate = Double(failures) / Double(totalTests)

        return DNSResult(
            averageResolutionTime: medianTime,
            failureRate: failureRate
        )
    }
}
