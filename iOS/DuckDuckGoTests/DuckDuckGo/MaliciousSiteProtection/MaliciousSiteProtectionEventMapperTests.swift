//
//  MaliciousSiteProtectionEventMapperTests.swift
//  DuckDuckGo
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

import Common
import Foundation
import MaliciousSiteProtection
@_spi(Testing) import PixelKit
import Testing

@testable import DuckDuckGo

@Suite("Malicious Site Protection event mapper")
struct MaliciousSiteProtectionEventMapperTests {

    private let pixelKit = PixelKitMock()

    private var mapping: EventMapping<MaliciousSiteProtection.Event> {
        MaliciousSiteProtectionEventMapper.debugEvents(pixelFiring: { [pixelKit] in pixelKit })
    }

    @Test("Update time fires a daily and count pixel with the bucket in its name")
    func updateTime() {
        mapping.fire(.dataSetUpdateTime(category: .phishing, type: .hashPrefixSet, bucket: .upTo250ms))

        #expect(pixelKit.actualFireCalls == [
            ExpectedFireCall(pixel: MaliciousSiteProtectionDebugPixel.updateTime(category: .phishing, type: .hashPrefixSet, bucket: .upTo250ms), frequency: .dailyAndCount)
        ])
        #expect(pixelKit.actualFireCalls.first?.pixel.name == "m_debug_malicious-site-protection_update-time_phishing_hash-prefix_250ms")
    }

    @Test("Dataset size fires a daily and count pixel with the bucket in its name")
    func datasetSize() {
        mapping.fire(.dataSetSize(category: .scam, type: .filterSet, bucket: .upTo30mb))

        #expect(pixelKit.actualFireCalls == [
            ExpectedFireCall(pixel: MaliciousSiteProtectionDebugPixel.datasetSize(category: .scam, type: .filterSet, bucket: .upTo30mb), frequency: .dailyAndCount)
        ])
        #expect(pixelKit.actualFireCalls.first?.pixel.name == "m_debug_malicious-site-protection_dataset-size_scam_filter-set_30mb")
    }

    @Test("Aggregate update time fires a daily and count pixel with aggregate in place of the category")
    func aggregateUpdateTime() {
        mapping.fire(.dataSetAggregateUpdateTime(type: .filterSet, bucket: .upTo4s))

        #expect(pixelKit.actualFireCalls == [
            ExpectedFireCall(pixel: MaliciousSiteProtectionDebugPixel.aggregateUpdateTime(type: .filterSet, bucket: .upTo4s), frequency: .dailyAndCount)
        ])
        #expect(pixelKit.actualFireCalls.first?.pixel.name == "m_debug_malicious-site-protection_update-time_aggregate_filter-set_4s")
    }

    @Test("Aggregate dataset size fires a daily and count pixel with aggregate in place of the category")
    func aggregateDatasetSize() {
        mapping.fire(.dataSetAggregateSize(type: .hashPrefixSet, bucket: .upTo15mb))

        #expect(pixelKit.actualFireCalls == [
            ExpectedFireCall(pixel: MaliciousSiteProtectionDebugPixel.aggregateDatasetSize(type: .hashPrefixSet, bucket: .upTo15mb), frequency: .dailyAndCount)
        ])
        #expect(pixelKit.actualFireCalls.first?.pixel.name == "m_debug_malicious-site-protection_dataset-size_aggregate_hash-prefix_15mb")
    }

    @Test("Debug pixels carry no parameters of their own")
    func noParameters() {
        let pixel = MaliciousSiteProtectionDebugPixel.updateTime(category: .malware, type: .filterSet, bucket: .more)

        #expect(pixel.parameters == nil)
        #expect(pixel.standardParameters == nil)
    }

}
