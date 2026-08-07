//
//  AIChatContextualSheetViewControllerTests.swift
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

import UIKit
import XCTest
@testable import DuckDuckGo

final class AIChatContextualSheetViewControllerTests: XCTestCase {

    func test_keyboardDismissDragGate_onlyBeginsForPredominantlyVerticalDrags() {
        XCTAssertTrue(AIChatContextualSheetViewController.isPredominantlyVerticalDrag(velocity: CGPoint(x: 4, y: 120)))
        XCTAssertTrue(AIChatContextualSheetViewController.isPredominantlyVerticalDrag(velocity: CGPoint(x: -10, y: -300)))
        XCTAssertFalse(AIChatContextualSheetViewController.isPredominantlyVerticalDrag(velocity: CGPoint(x: 200, y: 30)))
        XCTAssertFalse(AIChatContextualSheetViewController.isPredominantlyVerticalDrag(velocity: CGPoint(x: 50, y: 50)))
    }
}
