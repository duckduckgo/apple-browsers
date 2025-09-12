//
//  SwitchBarSubmissionMetricsTests.swift
//  DuckDuckGo
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

import XCTest
@testable import DuckDuckGo

final class SwitchBarSubmissionMetricsTests: XCTestCase {
    
    // MARK: - SwitchBarTextBucket Tests
    
    func testTextBucketShort() {
        let bucket = SwitchBarTextBucket("hello")!
        XCTAssertEqual(bucket, .short)
        XCTAssertEqual(bucket.rawValue, "short")
    }
    
    func testTextBucketShortBoundary() {
        let bucket15 = SwitchBarTextBucket("123456789012345")!
        XCTAssertEqual(bucket15, .short)
        XCTAssertEqual(bucket15.rawValue, "short")
    }
    
    func testTextBucketMedium() {
        let bucket = SwitchBarTextBucket("This is a medium text")!
        XCTAssertEqual(bucket, .medium)
        XCTAssertEqual(bucket.rawValue, "medium")
    }
    
    func testTextBucketMediumBoundaries() {
        let bucket16 = SwitchBarTextBucket("1234567890123456")!
        XCTAssertEqual(bucket16, .medium)
        
        let bucket40 = SwitchBarTextBucket("1234567890123456789012345678901234567890")!
        XCTAssertEqual(bucket40, .medium)
    }
    
    func testTextBucketLong() {
        let bucket = SwitchBarTextBucket("This is a longer text that should be categorized as long text for testing purposes")!
        XCTAssertEqual(bucket, .long)
        XCTAssertEqual(bucket.rawValue, "long")
    }
    
    func testTextBucketLongBoundaries() {
        let bucket41 = SwitchBarTextBucket("12345678901234567890123456789012345678901")!
        XCTAssertEqual(bucket41, .long)
        
        let bucket99 = SwitchBarTextBucket(String(repeating: "a", count: 99))
        XCTAssertEqual(bucket99, .long)
        
        let bucket100 = SwitchBarTextBucket(String(repeating: "a", count: 100))
        XCTAssertEqual(bucket100, .long)
    }
    
    func testTextBucketVeryLong() {
        let longText = String(repeating: "a", count: 150)
        let bucket = SwitchBarTextBucket(longText)!
        XCTAssertEqual(bucket, .veryLong)
        XCTAssertEqual(bucket.rawValue, "very_long")
    }
    
    func testTextBucketVeryLongBoundary() {
        let bucket100 = SwitchBarTextBucket(String(repeating: "a", count: 100))!
        XCTAssertEqual(bucket100, .long)
        
        let bucket101 = SwitchBarTextBucket(String(repeating: "a", count: 101))!
        XCTAssertEqual(bucket101, .veryLong)
    }
    
    func testTextBucketEmptyString() {
        let bucket = SwitchBarTextBucket("")
        XCTAssertNil(bucket)
    }
    
    func testTextBucketSingleCharacter() {
        let bucket = SwitchBarTextBucket("a")!
        XCTAssertEqual(bucket, .short)
    }
    
    func testTextBucketUnicodeCharacters() {
        let unicodeText = "Hello 👋 World 🌍"
        let bucket = SwitchBarTextBucket(unicodeText)!
        XCTAssertEqual(bucket, .short)
    }
    
    // MARK: - SwitchBarSubmissionMetrics Tests
    
    func testSubmissionMetricsProcessSearchShort() {
        let metrics = SwitchBarSubmissionMetrics(featureDiscovery: MockFeatureDiscovery())
        let shortText = "test"
        
        metrics.process(shortText, for: .search)
    }
    
    func testSubmissionMetricsProcessAIChatMedium() {
        let metrics = SwitchBarSubmissionMetrics(featureDiscovery: MockFeatureDiscovery())
        let mediumText = "This is a medium length prompt for AI"
        
        metrics.process(mediumText, for: .aiChat)
    }
    
    func testSubmissionMetricsProcessSearchLong() {
        let metrics = SwitchBarSubmissionMetrics(featureDiscovery: MockFeatureDiscovery())
        let longText = "This is a very long search query that should be categorized as long text"
        
        metrics.process(longText, for: .search)
    }
    
    func testSubmissionMetricsProcessAIChatVeryLong() {
        let metrics = SwitchBarSubmissionMetrics(featureDiscovery: MockFeatureDiscovery())
        let veryLongText = String(repeating: "This is a very long prompt. ", count: 10)
        
        metrics.process(veryLongText, for: .aiChat)
    }
    
    func testSubmissionMetricsProcessEmptyTextReturnsEarly() {
        let metrics = SwitchBarSubmissionMetrics(featureDiscovery: MockFeatureDiscovery())
        
        // Should return early without firing pixels
        metrics.process("", for: .search)
        metrics.process("", for: .aiChat)
    }
    
    // MARK: - Feature Discovery Tests
    
    func testAIChatSubmissionCallsSetWasUsedBefore() {
        let mockFeatureDiscovery = MockFeatureDiscovery()
        let metrics = SwitchBarSubmissionMetrics(featureDiscovery: mockFeatureDiscovery)
        
        metrics.process("test prompt", for: .aiChat)
        
        XCTAssertTrue(mockFeatureDiscovery.wasSetWasUsedBeforeCalled(for: .aiChat))
        XCTAssertEqual(mockFeatureDiscovery.setWasUsedBeforeCallCount, 1)
    }
    
    func testSearchSubmissionDoesNotCallSetWasUsedBefore() {
        let mockFeatureDiscovery = MockFeatureDiscovery()
        let metrics = SwitchBarSubmissionMetrics(featureDiscovery: mockFeatureDiscovery)
        
        metrics.process("test query", for: .search)
        
        XCTAssertFalse(mockFeatureDiscovery.wasSetWasUsedBeforeCalled(for: .aiChat))
        XCTAssertEqual(mockFeatureDiscovery.setWasUsedBeforeCallCount, 0)
    }
    
    func testAIChatSubmissionWithFirstTimeUser() {
        let mockFeatureDiscovery = MockFeatureDiscovery()
        mockFeatureDiscovery.setReturnValue(false, for: .aiChat)
        let metrics = SwitchBarSubmissionMetrics(featureDiscovery: mockFeatureDiscovery)
        
        metrics.process("first prompt", for: .aiChat)
        
        XCTAssertTrue(mockFeatureDiscovery.wasSetWasUsedBeforeCalled(for: .aiChat))
    }
    
    func testAIChatSubmissionWithReturningUser() {
        let mockFeatureDiscovery = MockFeatureDiscovery()
        mockFeatureDiscovery.setReturnValue(true, for: .aiChat)
        let metrics = SwitchBarSubmissionMetrics(featureDiscovery: mockFeatureDiscovery)
        
        metrics.process("another prompt", for: .aiChat)
        
        XCTAssertTrue(mockFeatureDiscovery.wasSetWasUsedBeforeCalled(for: .aiChat))
    }
    
    func testMultipleAIChatSubmissionsOnlyCallSetWasUsedBeforeMultipleTimes() {
        let mockFeatureDiscovery = MockFeatureDiscovery()
        let metrics = SwitchBarSubmissionMetrics(featureDiscovery: mockFeatureDiscovery)
        
        metrics.process("first prompt", for: .aiChat)
        metrics.process("second prompt", for: .aiChat)
        metrics.process("third prompt", for: .aiChat)
        
        XCTAssertEqual(mockFeatureDiscovery.setWasUsedBeforeCallCount, 3)
    }

}
