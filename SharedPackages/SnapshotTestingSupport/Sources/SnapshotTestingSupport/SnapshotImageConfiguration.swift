//
//  SnapshotImageConfiguration.swift
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

public struct SnapshotImageConfiguration: Equatable {
    public let appearance: SnapshotAppearance
    public let device: SnapshotDevice?
    public let name: String
    public let size: CGSize?

    public init(
        appearance: SnapshotAppearance,
        device: SnapshotDevice? = nil,
        name: String? = nil,
        size: CGSize? = nil
    ) {
        self.appearance = appearance
        self.device = device
        self.name = name ?? SnapshotNameGenerator.name(for: appearance, device: device)
        self.size = size
    }

    func resolvedSize(defaultSize: CGSize) -> CGSize {
        size ?? device?.size ?? defaultSize
    }
}
