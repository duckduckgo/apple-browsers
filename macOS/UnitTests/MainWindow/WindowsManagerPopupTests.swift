//
//  WindowsManagerPopupTests.swift
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
import Cocoa

@testable import DuckDuckGo_Privacy_Browser

final class WindowsManagerPopupTests: XCTestCase {

    // MARK: - Content Size Tests

    @MainActor
    func testWhenContentSizeIsZero_thenDefaultSizeIsUsed() {
        let visibleScreenFrame = NSRect(x: 100, y: 50, width: 2000, height: 1500)

        let (_, contentSize) = WindowsManager.calculatePopupFrame(
            screenFrame: visibleScreenFrame,
            origin: nil,
            contentSize: nil
        )

        XCTAssertEqual(contentSize.width, WindowsManager.Constants.defaultPopUpWidth)
        XCTAssertEqual(contentSize.height, WindowsManager.Constants.defaultPopUpHeight)
    }

    @MainActor
    func testWhenContentSizeIsBelowMinimum_thenMinimumSizeIsEnforced() {
        let visibleScreenFrame = NSRect(x: -200, y: 100, width: 2000, height: 1500)

        let (_, contentSize) = WindowsManager.calculatePopupFrame(
            screenFrame: visibleScreenFrame,
            origin: nil,
            contentSize: NSSize(width: 50, height: 50)
        )

        XCTAssertEqual(contentSize.width, WindowsManager.Constants.minimumPopUpWidth)
        XCTAssertEqual(contentSize.height, WindowsManager.Constants.minimumPopUpHeight)
    }

    @MainActor
    func testWhenOnlyWidthIsBelowMinimum_thenOnlyWidthIsEnforced() {
        let visibleScreenFrame = NSRect(x: 0, y: 0, width: 2000, height: 1500)
        // Width below minimum, height valid
        let requestedSize = NSSize(width: 100, height: 600)

        let (_, contentSize) = WindowsManager.calculatePopupFrame(
            screenFrame: visibleScreenFrame,
            origin: nil,
            contentSize: requestedSize
        )

        // Width should be enforced to minimum
        XCTAssertEqual(contentSize.width, WindowsManager.Constants.minimumPopUpWidth)
        // Height should remain as requested (valid)
        XCTAssertEqual(contentSize.height, 600)
    }

    @MainActor
    func testWhenOnlyHeightIsBelowMinimum_thenOnlyHeightIsEnforced() {
        let visibleScreenFrame = NSRect(x: 200, y: -100, width: 2000, height: 1500)
        // Width valid, height below minimum
        let requestedSize = NSSize(width: 700, height: 100)

        let (_, contentSize) = WindowsManager.calculatePopupFrame(
            screenFrame: visibleScreenFrame,
            origin: nil,
            contentSize: requestedSize
        )

        // Width should remain as requested (valid)
        XCTAssertEqual(contentSize.width, 700)
        // Height should be enforced to minimum
        XCTAssertEqual(contentSize.height, WindowsManager.Constants.minimumPopUpHeight)
    }

    @MainActor
    func testWhenContentSizeIsExactlyMinimum_thenSizeIsPreserved() {
        let visibleScreenFrame = NSRect(x: 0, y: 0, width: 2000, height: 1500)
        // Request exactly minimum dimensions
        let requestedSize = NSSize(
            width: WindowsManager.Constants.minimumPopUpWidth,
            height: WindowsManager.Constants.minimumPopUpHeight
        )

        let (_, contentSize) = WindowsManager.calculatePopupFrame(
            screenFrame: visibleScreenFrame,
            origin: nil,
            contentSize: requestedSize
        )

        XCTAssertEqual(contentSize.width, WindowsManager.Constants.minimumPopUpWidth)
        XCTAssertEqual(contentSize.height, WindowsManager.Constants.minimumPopUpHeight)
    }

    @MainActor
    func testWhenContentSizeIsValidBetweenMinAndMax_thenSizeIsPreserved() {
        let visibleScreenFrame = NSRect(x: 100, y: 50, width: 2000, height: 1500)
        // Request valid size between minimum and screen
        let requestedSize = NSSize(width: 800, height: 600)

        let (_, contentSize) = WindowsManager.calculatePopupFrame(
            screenFrame: visibleScreenFrame,
            origin: nil,
            contentSize: requestedSize
        )

        // Size should be preserved as-is
        XCTAssertEqual(contentSize.width, 800)
        XCTAssertEqual(contentSize.height, 600)
    }

    @MainActor
    func testWhenContentSizeExceedsScreen_thenSizeIsConstrainedToScreen() {
        let visibleScreenFrame = NSRect(x: 0, y: 0, width: 800, height: 600)

        let (_, contentSize) = WindowsManager.calculatePopupFrame(
            screenFrame: visibleScreenFrame,
            origin: nil,
            contentSize: NSSize(width: 2000, height: 1500)
        )

        XCTAssertEqual(contentSize.width, 800)
        XCTAssertEqual(contentSize.height, 600)
    }

    @MainActor
    func testWhenContentSizeExceedsScreenWithPositiveOrigin_thenSizeIsConstrainedToScreen() {
        // Small screen with positive origin (secondary monitor scenario)
        let visibleScreenFrame = NSRect(x: 1920, y: 200, width: 1024, height: 768)
        // Request popup larger than screen
        let requestedSize = NSSize(width: 3000, height: 2000)

        let (_, contentSize) = WindowsManager.calculatePopupFrame(
            screenFrame: visibleScreenFrame,
            origin: NSPoint(x: 100, y: 100),
            contentSize: requestedSize
        )

        // Should be constrained to screen dimensions
        XCTAssertEqual(contentSize.width, 1024)
        XCTAssertEqual(contentSize.height, 768)
    }

    @MainActor
    func testWhenContentSizeExceedsVerySmallScreen_thenMinimumIsEnforcedOverScreenSize() {
        // Very small screen (smaller than minimum popup dimensions)
        let visibleScreenFrame = NSRect(x: 500, y: 300, width: 400, height: 200)
        // Request any size (even small)
        let requestedSize = NSSize(width: 300, height: 150)

        let (_, contentSize) = WindowsManager.calculatePopupFrame(
            screenFrame: visibleScreenFrame,
            origin: NSPoint(x: 50, y: 50),
            contentSize: requestedSize
        )

        // Minimum should still be enforced even if larger than screen
        // Width: min is 512, screen is 400 -> should be 400 (screen wins)
        XCTAssertEqual(contentSize.width, 400)
        // Height: min is 258, screen is 200 -> should be 200 (screen wins)
        XCTAssertEqual(contentSize.height, 200)
    }

    // MARK: - Dock and Menu Bar Tests

    @MainActor
    func testWhenScreenHasMenuBarAtTop_thenPopupStaysWithinVisibleFrame() {
        // Simulate 1920x1080 screen with 25px menu bar at top
        // visibleFrame in macOS coordinates: y=0 to y=1055 (1080 - 25)
        let visibleScreenFrame = NSRect(x: 0, y: 0, width: 1920, height: 1055)
        let contentSize = NSSize(width: 400, height: 300)

        // Request popup at top of screen (y=0 in web coordinates = top of visible frame)
        let origin = NSPoint(x: 500, y: 0)

        let (droppingPoint, finalContentSize) = WindowsManager.calculatePopupFrame(
            screenFrame: visibleScreenFrame,
            origin: origin,
            contentSize: contentSize
        )

        XCTAssertNotNil(droppingPoint)
        // droppingPoint.y is the TOP edge of the window
        // It should not exceed visibleScreenFrame.maxY (menu bar boundary)
        XCTAssertLessThanOrEqual(droppingPoint!.y, visibleScreenFrame.maxY)
        // The bottom edge should not go below visibleScreenFrame.minY
        XCTAssertGreaterThanOrEqual(droppingPoint!.y - finalContentSize.height, visibleScreenFrame.minY)
    }

    @MainActor
    func testWhenScreenHasDockAtBottom_thenPopupStaysAboveDock() {
        // Simulate 1920x1080 screen with 75px dock at bottom
        // visibleFrame: starts at y=75 (dock height), extends to y=1080
        let visibleScreenFrame = NSRect(x: 0, y: 75, width: 1920, height: 1005)
        let contentSize = NSSize(width: 400, height: 300)

        // Request popup near bottom of screen (high y in web coordinates = near bottom visually)
        let origin = NSPoint(x: 500, y: 900)

        let (droppingPoint, finalContentSize) = WindowsManager.calculatePopupFrame(
            screenFrame: visibleScreenFrame,
            origin: origin,
            contentSize: contentSize
        )

        XCTAssertNotNil(droppingPoint)
        // droppingPoint.y is the TOP edge of the window
        // The bottom edge (droppingPoint.y - height) should not go below visibleScreenFrame.minY (75)
        XCTAssertGreaterThanOrEqual(droppingPoint!.y - finalContentSize.height, visibleScreenFrame.minY - 1.0)
    }

    @MainActor
    func testWhenScreenHasDockOnLeft_thenPopupStaysRightOfDock() {
        // Simulate 1920x1080 screen with 75px dock on left side
        // visibleFrame: starts at x=75 (dock width)
        let visibleScreenFrame = NSRect(x: 75, y: 0, width: 1845, height: 1080)
        let contentSize = NSSize(width: 400, height: 300)

        // Request popup at far left
        let origin = NSPoint(x: 0, y: 500)

        let (droppingPoint, finalContentSize) = WindowsManager.calculatePopupFrame(
            screenFrame: visibleScreenFrame,
            origin: origin,
            contentSize: contentSize
        )

        XCTAssertNotNil(droppingPoint)
        // Popup should stay to the right of the dock
        // The left edge should not go below visibleScreenFrame.minX (75)
        XCTAssertGreaterThanOrEqual(droppingPoint!.x - finalContentSize.width / 2, visibleScreenFrame.minX - 1.0)
    }

    @MainActor
    func testWhenScreenHasDockOnRight_thenPopupStaysLeftOfDock() {
        // Simulate 1920x1080 screen with 75px dock on right side
        // visibleFrame: width reduced by 75
        let visibleScreenFrame = NSRect(x: 0, y: 0, width: 1845, height: 1080)
        let contentSize = NSSize(width: 400, height: 300)

        // Request popup at far right
        let origin = NSPoint(x: 1900, y: 500)

        let (droppingPoint, finalContentSize) = WindowsManager.calculatePopupFrame(
            screenFrame: visibleScreenFrame,
            origin: origin,
            contentSize: contentSize
        )

        XCTAssertNotNil(droppingPoint)
        // Popup should stay to the left of the dock
        // The right edge should not exceed visibleScreenFrame.maxX
        XCTAssertLessThanOrEqual(droppingPoint!.x + finalContentSize.width / 2, visibleScreenFrame.maxX + 1.0)
    }

    // MARK: - Screen Boundary Tests

    @MainActor
    func testWhenPopupExceedsLeftBorder_thenItIsConstrainedToScreen() {
        // Multi-monitor setup: second screen to the right of main
        let visibleScreenFrame = NSRect(x: 1920, y: 100, width: 1920, height: 1080)
        // Request size below minimum to test enforcement
        let requestedSize = NSSize(width: 100, height: 50)

        // Request popup far to the left of screen origin
        let origin = NSPoint(x: -500, y: 200)

        let (droppingPoint, finalContentSize) = WindowsManager.calculatePopupFrame(
            screenFrame: visibleScreenFrame,
            origin: origin,
            contentSize: requestedSize
        )

        XCTAssertNotNil(droppingPoint)
        // Minimum dimensions should be enforced
        XCTAssertGreaterThanOrEqual(finalContentSize.width, WindowsManager.Constants.minimumPopUpWidth)
        XCTAssertGreaterThanOrEqual(finalContentSize.height, WindowsManager.Constants.minimumPopUpHeight)
        // Left edge should not go below visibleScreenFrame.minX (1920)
        let leftEdge = droppingPoint!.x - finalContentSize.width / 2
        XCTAssertGreaterThanOrEqual(leftEdge, visibleScreenFrame.minX - 1.0)
        XCTAssertLessThanOrEqual(droppingPoint!.x + finalContentSize.width / 2, visibleScreenFrame.maxX + 1.0)
    }

    @MainActor
    func testWhenPopupExceedsRightBorder_thenItIsConstrainedToScreen() {
        // Screen with negative origin (to the left of main)
        let visibleScreenFrame = NSRect(x: -1920, y: 50, width: 1920, height: 1080)
        // Request size below minimum to test enforcement
        let requestedSize = NSSize(width: 200, height: 100)

        // Request popup far to the right
        let origin = NSPoint(x: 5000, y: 200)

        let (droppingPoint, finalContentSize) = WindowsManager.calculatePopupFrame(
            screenFrame: visibleScreenFrame,
            origin: origin,
            contentSize: requestedSize
        )

        XCTAssertNotNil(droppingPoint)
        // Minimum dimensions should be enforced
        XCTAssertGreaterThanOrEqual(finalContentSize.width, WindowsManager.Constants.minimumPopUpWidth)
        XCTAssertGreaterThanOrEqual(finalContentSize.height, WindowsManager.Constants.minimumPopUpHeight)
        // Right edge should not exceed visibleScreenFrame.maxX (0)
        let rightEdge = droppingPoint!.x + finalContentSize.width / 2
        XCTAssertLessThanOrEqual(rightEdge, visibleScreenFrame.maxX + 1.0)
        XCTAssertGreaterThanOrEqual(droppingPoint!.x - finalContentSize.width / 2, visibleScreenFrame.minX - 1.0)
    }

    @MainActor
    func testWhenPopupExceedsTopBorder_thenItIsConstrainedToScreen() {
        // Screen with positive Y origin
        let visibleScreenFrame = NSRect(x: 100, y: 1200, width: 1920, height: 1080)
        // Request size below minimum to test enforcement
        let requestedSize = NSSize(width: 300, height: 150)

        // Request popup very near top (y=0 means top in web coordinates)
        let origin = NSPoint(x: 500, y: 0)

        let (droppingPoint, finalContentSize) = WindowsManager.calculatePopupFrame(
            screenFrame: visibleScreenFrame,
            origin: origin,
            contentSize: requestedSize
        )

        XCTAssertNotNil(droppingPoint)
        // Minimum dimensions should be enforced
        XCTAssertGreaterThanOrEqual(finalContentSize.width, WindowsManager.Constants.minimumPopUpWidth)
        XCTAssertGreaterThanOrEqual(finalContentSize.height, WindowsManager.Constants.minimumPopUpHeight)
        // Top edge should not exceed visibleScreenFrame.maxY
        XCTAssertLessThanOrEqual(droppingPoint!.y, visibleScreenFrame.maxY + 1.0)
        // Bottom edge should not go below visibleScreenFrame.minY
        XCTAssertGreaterThanOrEqual(droppingPoint!.y - finalContentSize.height, visibleScreenFrame.minY - 1.0)
    }

    @MainActor
    func testWhenPopupExceedsBottomBorder_thenItIsConstrainedToScreen() {
        // Screen with negative Y origin
        let visibleScreenFrame = NSRect(x: 0, y: -1000, width: 1920, height: 900)
        // Request size below minimum to test enforcement
        let requestedSize = NSSize(width: 250, height: 200)

        // Request popup near bottom (high y in web coordinates)
        let origin = NSPoint(x: 500, y: 2000)

        let (droppingPoint, finalContentSize) = WindowsManager.calculatePopupFrame(
            screenFrame: visibleScreenFrame,
            origin: origin,
            contentSize: requestedSize
        )

        XCTAssertNotNil(droppingPoint)
        // Minimum dimensions should be enforced
        XCTAssertGreaterThanOrEqual(finalContentSize.width, WindowsManager.Constants.minimumPopUpWidth)
        XCTAssertGreaterThanOrEqual(finalContentSize.height, WindowsManager.Constants.minimumPopUpHeight)
        // Bottom edge should not go below visibleScreenFrame.minY (-1000)
        let bottomEdge = droppingPoint!.y - finalContentSize.height
        XCTAssertGreaterThanOrEqual(bottomEdge, visibleScreenFrame.minY - 1.0)
        // Top edge should not exceed visibleScreenFrame.maxY
        XCTAssertLessThanOrEqual(droppingPoint!.y, visibleScreenFrame.maxY + 1.0)
    }

    @MainActor
    func testWhenPopupExceedsAllBorders_thenItIsFullyConstrainedToScreen() {
        // Screen with arbitrary positive origin
        let visibleScreenFrame = NSRect(x: 500, y: 300, width: 1600, height: 1000)
        // Request size below minimum to test enforcement
        let requestedSize = NSSize(width: 150, height: 80)

        // Request popup far outside all borders
        let origin = NSPoint(x: -1000, y: -500)

        let (droppingPoint, finalContentSize) = WindowsManager.calculatePopupFrame(
            screenFrame: visibleScreenFrame,
            origin: origin,
            contentSize: requestedSize
        )

        XCTAssertNotNil(droppingPoint)

        // Minimum dimensions should be enforced even when exceeding all borders
        XCTAssertGreaterThanOrEqual(finalContentSize.width, WindowsManager.Constants.minimumPopUpWidth)
        XCTAssertGreaterThanOrEqual(finalContentSize.height, WindowsManager.Constants.minimumPopUpHeight)

        // Validate all edges are within screen bounds
        let leftEdge = droppingPoint!.x - finalContentSize.width / 2
        let rightEdge = droppingPoint!.x + finalContentSize.width / 2
        let topEdge = droppingPoint!.y
        let bottomEdge = droppingPoint!.y - finalContentSize.height

        XCTAssertGreaterThanOrEqual(leftEdge, visibleScreenFrame.minX - 1.0, "Left edge exceeds screen")
        XCTAssertLessThanOrEqual(rightEdge, visibleScreenFrame.maxX + 1.0, "Right edge exceeds screen")
        XCTAssertLessThanOrEqual(topEdge, visibleScreenFrame.maxY + 1.0, "Top edge exceeds screen")
        XCTAssertGreaterThanOrEqual(bottomEdge, visibleScreenFrame.minY - 1.0, "Bottom edge exceeds screen")
    }

    @MainActor
    func testWhenNoOriginProvided_thenDroppingPointIsNil() {
        let visibleScreenFrame = NSRect(x: -500, y: 200, width: 2000, height: 1500)
        // Use size above minimum to avoid enforcement
        let requestedSize = NSSize(width: 600, height: 400)

        let (droppingPoint, contentSize) = WindowsManager.calculatePopupFrame(
            screenFrame: visibleScreenFrame,
            origin: nil,
            contentSize: requestedSize
        )

        XCTAssertNil(droppingPoint)
        XCTAssertEqual(contentSize.width, requestedSize.width)
        XCTAssertEqual(contentSize.height, requestedSize.height)
    }

    // MARK: - Coordinate System Tests

    @MainActor
    func testCoordinateSystemConversion_zeroOriginScreen() {
        // Test that web coordinates (top-left origin) are correctly converted to AppKit coordinates
        let visibleScreenFrame = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        // Use size above minimum to test coordinate math without enforcement side-effects
        let contentSize = NSSize(width: 600, height: 400)

        // Web coordinates: (100, 50) means 100px from left, 50px from top
        let webOrigin = NSPoint(x: 100, y: 50)

        let (droppingPoint, _) = WindowsManager.calculatePopupFrame(
            screenFrame: visibleScreenFrame,
            origin: webOrigin,
            contentSize: contentSize
        )

        XCTAssertNotNil(droppingPoint)
        // droppingPoint.x should be center: screenFrame.minX + 100 + 600/2 = 0 + 100 + 300 = 400
        XCTAssertEqual(droppingPoint!.x, 400, accuracy: 1.0)
        // droppingPoint.y should be top edge in AppKit: screenFrame.maxY - 50 = 1080 - 50 = 1030
        XCTAssertEqual(droppingPoint!.y, 1030, accuracy: 1.0)
    }

    @MainActor
    func testCoordinateSystemConversion_positiveOriginScreen() {
        // Test coordinate conversion with screen at positive origin (second monitor)
        let visibleScreenFrame = NSRect(x: 1920, y: 200, width: 1920, height: 1080)
        // Use size above minimum to test coordinate math without enforcement side-effects
        let contentSize = NSSize(width: 600, height: 400)

        // Web coordinates: (150, 100)
        let webOrigin = NSPoint(x: 150, y: 100)

        let (droppingPoint, _) = WindowsManager.calculatePopupFrame(
            screenFrame: visibleScreenFrame,
            origin: webOrigin,
            contentSize: contentSize
        )

        XCTAssertNotNil(droppingPoint)
        // droppingPoint.x: screenFrame.minX + 150 + 600/2 = 1920 + 150 + 300 = 2370
        XCTAssertEqual(droppingPoint!.x, 2370, accuracy: 1.0)
        // droppingPoint.y: screenFrame.maxY - 100 = (200 + 1080) - 100 = 1180
        XCTAssertEqual(droppingPoint!.y, 1180, accuracy: 1.0)
    }

    @MainActor
    func testCoordinateSystemConversion_negativeOriginScreen() {
        // Test coordinate conversion with screen at negative origin (monitor to the left)
        let visibleScreenFrame = NSRect(x: -1920, y: -100, width: 1920, height: 1080)
        // Use size above minimum to test coordinate math without enforcement side-effects
        let contentSize = NSSize(width: 600, height: 400)

        // Web coordinates: (200, 80)
        let webOrigin = NSPoint(x: 200, y: 80)

        let (droppingPoint, _) = WindowsManager.calculatePopupFrame(
            screenFrame: visibleScreenFrame,
            origin: webOrigin,
            contentSize: contentSize
        )

        XCTAssertNotNil(droppingPoint)
        // droppingPoint.x: screenFrame.minX + 200 + 600/2 = -1920 + 200 + 300 = -1420
        XCTAssertEqual(droppingPoint!.x, -1420, accuracy: 1.0)
        // droppingPoint.y: screenFrame.maxY - 80 = (-100 + 1080) - 80 = 900
        XCTAssertEqual(droppingPoint!.y, 900, accuracy: 1.0)
    }

}
