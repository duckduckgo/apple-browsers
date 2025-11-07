//
//  BucketModifier.swift
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

struct Bucket {
    var version: Int
    var value: Int
}

protocol BucketModifier {

    /// Convert a Int value in it's bucketed int version based on the bucket configuration received from the privacy configuration.
    /// Returns a Bucket containing both the bucketed value and the configuration version.
    func bucket(value: Int, pixelName: AttributedMetricPixelName) throws -> Bucket

    func parseConfigurations(from settings: [String: Any]) throws
}

// https://app.asana.com/1/137249556945/project/1113117197328546/task/1211362861225166?focus=true

final class DefaultBucketModifier: BucketModifier {

    struct BucketConfiguration: Codable {
        let buckets: [Int]
        let version: Int
    }

    private var configurations: [String: BucketConfiguration] = [:]

    public func parseConfigurations(from settings: [String: Any]) throws {
        var configurations: [String: BucketConfiguration] = [:]

        for (key, value) in settings {
            guard let configDict = value as? [String: Any] else {
                throw BucketModifierError.invalidConfiguration
            }

            guard let buckets = configDict["buckets"] as? [Int],
                  let version = configDict["version"] as? Int else {
                throw BucketModifierError.invalidConfiguration
            }

            configurations[key] = BucketConfiguration(buckets: buckets, version: version)
        }

        self.configurations = configurations
    }

    func bucket(value: Int, pixelName: AttributedMetricPixelName) throws -> Bucket {
        guard let configuration = configurations[pixelName.rawValue] else {
            Logger.attributedMetric.error("The pixel bucket configuration is missing")
            throw BucketModifierError.missingConfiguration
        }

        let buckets = configuration.buckets
        let bucketedValue: Int

        // Find the index of the first bucket threshold that the value is less than or equal to
        if let matchIndex = buckets.firstIndex(where: { value <= $0 }) {
            bucketedValue = matchIndex
        } else {
            // If no match is found (value exceeds all thresholds), return the last bucket index
            bucketedValue = buckets.count
        }

        return Bucket(version: configuration.version, value: bucketedValue)
    }
}

enum BucketModifierError: Error {
    case invalidConfiguration
    case missingConfiguration
}
