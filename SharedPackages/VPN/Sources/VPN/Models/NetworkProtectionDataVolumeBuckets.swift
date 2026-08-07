//
//  NetworkProtectionDataVolumeBuckets.swift
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

public struct NetworkProtectionDataVolumeBuckets: Codable, Equatable, Sendable {
    private static let tenMiB: Int64 = 10 * 1024 * 1024
    private static let oneHundredMiB: Int64 = 100 * 1024 * 1024

    public let bytesSentBucket: String
    public let bytesReceivedBucket: String

    public init(dataVolume: DataVolume) {
        self.init(
            bytesSent: dataVolume.bytesSent,
            bytesReceived: dataVolume.bytesReceived
        )
    }

    public init(bytesSent: Int64 = 0,
                bytesReceived: Int64 = 0) {
        self.bytesSentBucket = Self.bucketLabel(for: bytesSent)
        self.bytesReceivedBucket = Self.bucketLabel(for: bytesReceived)
    }

    private static func bucketLabel(for value: Int64) -> String {
        guard value > 0 else {
            return "0"
        }

        switch value {
        case ..<tenMiB:
            return "<10 MiB"
        case ..<oneHundredMiB:
            return "10-100 MiB"
        default:
            return "100 MiB+"
        }
    }
}
