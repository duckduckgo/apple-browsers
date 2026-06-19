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
import Testing

@Suite("Snapshot Image Size Tests")
struct SnapshotImageSizeTests {

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func intrinsicContentSizeUsesConfigurationSizeWhenProvided() {
        let configuration = SnapshotImageConfiguration(
            appearance: .light,
            size: CGSize(width: 320, height: 240)
        )

        #expect(
            SnapshotImageSize.intrinsicContentSize.resolvedSize(
                for: configuration,
                defaultSize: SnapshotDevice.iPhoneDefault.size
            ) == CGSize(width: 320, height: 240)
        )
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func intrinsicContentSizeDefersToViewWhenConfigurationHasNoSize() {
        #expect(
            SnapshotImageSize.intrinsicContentSize.resolvedSize(
                for: SnapshotImageConfiguration(appearance: .light),
                defaultSize: SnapshotDevice.iPhoneDefault.size
            ) == nil
        )
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func constrainedWidthDefersHeightToView() {
        #expect(
            SnapshotImageSize.constrainedWidth.resolvedSize(
                for: SnapshotImageConfiguration(appearance: .light),
                defaultSize: SnapshotDevice.iPhoneDefault.size
            ) == nil
        )
        #expect(SnapshotImageSize.constrainedWidth.fixedConstrainedWidth == SnapshotDevice.iPhoneDefault.size.width)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func screenUsesConfigurationDeviceSize() {
        let configuration = SnapshotImageConfiguration(
            appearance: .dark,
            device: .iPadDefault
        )

        #expect(
            SnapshotImageSize.screen.resolvedSize(
                for: configuration,
                defaultSize: SnapshotDevice.iPhoneDefault.size
            ) == SnapshotDevice.iPadDefault.size
        )
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func sheetUsesConfigurationDeviceSize() {
        let configuration = SnapshotImageConfiguration(
            appearance: .dark,
            device: .iPadDefault
        )

        #expect(
            SnapshotImageSize.sheet.resolvedSize(
                for: configuration,
                defaultSize: SnapshotDevice.iPhoneDefault.size
            ) == SnapshotDevice.iPadDefault.size
        )
        #expect(SnapshotImageSize.sheet.fixedConstrainedWidth == nil)
        #expect(SnapshotImageSize.sheet.usesDefaultIOSDevices)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func fixedUsesExplicitSize() {
        let size = CGSize(width: 500, height: 700)

        #expect(
            SnapshotImageSize.fixed(size).resolvedSize(
                for: SnapshotImageConfiguration(appearance: .light),
                defaultSize: SnapshotDevice.iPhoneDefault.size
            ) == size
        )
    }
}
