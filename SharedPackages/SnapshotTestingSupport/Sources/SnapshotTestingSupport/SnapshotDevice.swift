//
//  SnapshotDevice.swift
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

public struct SnapshotDevice: Equatable {
    public let name: String
    public let size: CGSize

    public init(
        name: String,
        size: CGSize
    ) {
        self.name = name
        self.size = size
    }

    public static let iPhoneDefault = SnapshotDevice(
        name: "iPhoneDefault",
        size: CGSize(width: 390, height: 844)
    )

    public static let iPadDefault = SnapshotDevice(
        name: "iPadDefault",
        size: CGSize(width: 820, height: 1180)
    )

    public static let defaultIOSDevices: [SnapshotDevice] = [
        .iPhoneDefault,
        .iPadDefault
    ]

    public static let macOSDefaultSize = CGSize(width: 800, height: 600)
}
