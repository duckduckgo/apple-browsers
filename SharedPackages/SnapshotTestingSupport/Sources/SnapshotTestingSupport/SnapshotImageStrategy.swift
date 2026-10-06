//
//  SnapshotImageStrategy.swift
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

public enum SnapshotImageStrategy: Equatable {
    case single(SnapshotAppearance)
    case allAppearances
    case custom([SnapshotImageConfiguration])

    public func configurations(
        for platform: SnapshotPlatform,
        size: SnapshotImageSize
    ) -> [SnapshotImageConfiguration] {
        switch self {
        case .single(let appearance):
            return configurations(for: platform, size: size, appearances: [appearance])
        case .allAppearances:
            return configurations(for: platform, size: size, appearances: SnapshotAppearance.allCases)
        case .custom(let configurations):
            return configurations
        }
    }

    private func configurations(
        for platform: SnapshotPlatform,
        size: SnapshotImageSize,
        appearances: [SnapshotAppearance]
    ) -> [SnapshotImageConfiguration] {
        switch platform {
        case .iOS where size.usesDefaultIOSDevices:
            return SnapshotDevice.defaultIOSDevices.flatMap { device in
                appearances.map {
                    SnapshotImageConfiguration(appearance: $0, device: device)
                }
            }
        case .iOS, .macOS:
            return appearances.map {
                SnapshotImageConfiguration(appearance: $0)
            }
        }
    }
}
