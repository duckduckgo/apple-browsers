//
//  SnapshotImageSizeTests.swift
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

import CoreGraphics
@testable import SnapshotTestingSupport
import XCTest

final class SnapshotImageSizeTests: XCTestCase {

    func testIntrinsicContentSizeUsesConfigurationSizeWhenProvided() {
        let configuration = SnapshotImageConfiguration(
            appearance: .light,
            size: CGSize(width: 320, height: 240)
        )

        XCTAssertEqual(
            SnapshotImageSize.intrinsicContentSize.resolvedSize(
                for: configuration,
                defaultSize: SnapshotDevice.iPhoneDefault.size
            ),
            CGSize(width: 320, height: 240)
        )
    }

    func testIntrinsicContentSizeDefersToViewWhenConfigurationHasNoSize() {
        XCTAssertNil(
            SnapshotImageSize.intrinsicContentSize.resolvedSize(
                for: SnapshotImageConfiguration(appearance: .light),
                defaultSize: SnapshotDevice.iPhoneDefault.size
            )
        )
    }

    func testConstrainedWidthDefersHeightToView() {
        XCTAssertNil(
            SnapshotImageSize.constrainedWidth.resolvedSize(
                for: SnapshotImageConfiguration(appearance: .light),
                defaultSize: SnapshotDevice.iPhoneDefault.size
            )
        )
        XCTAssertEqual(SnapshotImageSize.constrainedWidth.fixedConstrainedWidth, SnapshotDevice.iPhoneDefault.size.width)
    }

    func testScreenUsesConfigurationDeviceSize() {
        let configuration = SnapshotImageConfiguration(
            appearance: .dark,
            device: .iPadDefault
        )

        XCTAssertEqual(
            SnapshotImageSize.screen.resolvedSize(
                for: configuration,
                defaultSize: SnapshotDevice.iPhoneDefault.size
            ),
            SnapshotDevice.iPadDefault.size
        )
    }

    func testSheetUsesConfigurationDeviceSize() {
        let configuration = SnapshotImageConfiguration(
            appearance: .dark,
            device: .iPadDefault
        )

        XCTAssertEqual(
            SnapshotImageSize.sheet.resolvedSize(
                for: configuration,
                defaultSize: SnapshotDevice.iPhoneDefault.size
            ),
            SnapshotDevice.iPadDefault.size
        )
        XCTAssertNil(SnapshotImageSize.sheet.fixedConstrainedWidth)
        XCTAssertTrue(SnapshotImageSize.sheet.usesDefaultIOSDevices)
    }

    func testFixedUsesExplicitSize() {
        let size = CGSize(width: 500, height: 700)

        XCTAssertEqual(
            SnapshotImageSize.fixed(size).resolvedSize(
                for: SnapshotImageConfiguration(appearance: .light),
                defaultSize: SnapshotDevice.iPhoneDefault.size
            ),
            size
        )
    }
}
