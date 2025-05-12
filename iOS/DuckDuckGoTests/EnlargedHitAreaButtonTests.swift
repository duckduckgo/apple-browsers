//
//  EnlargedHitAreaButtonTests.swift
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

final class EnlargedHitAreaButtonTests: XCTestCase {
    
    func testDefaultHitTestBehavior() {
        // Given
        let button = EnlargedHitAreaButton(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        
        // When/Then
        // Test points inside the button bounds
        XCTAssertTrue(button.point(inside: CGPoint(x: 22, y: 22), with: nil))
        XCTAssertTrue(button.point(inside: CGPoint(x: 0, y: 0), with: nil))
        XCTAssertTrue(button.point(inside: CGPoint(x: 43, y: 43), with: nil))
        
        // Test points outside the button bounds
        XCTAssertFalse(button.point(inside: CGPoint(x: 44, y: 44), with: nil))
        XCTAssertFalse(button.point(inside: CGPoint(x: -1, y: 22), with: nil))
        XCTAssertFalse(button.point(inside: CGPoint(x: 45, y: 22), with: nil))
        XCTAssertFalse(button.point(inside: CGPoint(x: 22, y: -1), with: nil))
        XCTAssertFalse(button.point(inside: CGPoint(x: 22, y: 45), with: nil))
    }
    
    func testEnlargedHitTestBehavior() {
        // Given
        let button = EnlargedHitAreaButton(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        button.additionalHitTestSize = 10
        
        // When/Then
        // Test points inside the enlarged hit area
        XCTAssertTrue(button.point(inside: CGPoint(x: -5, y: 22), with: nil))
        XCTAssertTrue(button.point(inside: CGPoint(x: 49, y: 22), with: nil))
        XCTAssertTrue(button.point(inside: CGPoint(x: 22, y: -5), with: nil))
        XCTAssertTrue(button.point(inside: CGPoint(x: 22, y: 49), with: nil))
        
        // Test points outside the enlarged hit area
        XCTAssertFalse(button.point(inside: CGPoint(x: -11, y: 22), with: nil))
        XCTAssertFalse(button.point(inside: CGPoint(x: 55, y: 22), with: nil))
        XCTAssertFalse(button.point(inside: CGPoint(x: 22, y: -11), with: nil))
        XCTAssertFalse(button.point(inside: CGPoint(x: 22, y: 55), with: nil))
    }
    
    func testHitTestEdgeInsets() {
        // Given
        let button = EnlargedHitAreaButton(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        button.additionalHitTestSize = 10
        
        // When
        let edgeInsets = button.hitTestEdgeInsets
        
        // Then
        XCTAssertEqual(edgeInsets.top, -10)
        XCTAssertEqual(edgeInsets.left, -10)
        XCTAssertEqual(edgeInsets.bottom, -10)
        XCTAssertEqual(edgeInsets.right, -10)
    }
}
