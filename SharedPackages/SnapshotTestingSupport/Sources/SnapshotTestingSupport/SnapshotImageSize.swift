//
//  SnapshotImageSize.swift
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

public enum SnapshotImageSize: Equatable {
    case intrinsicContentSize
    case constrainedWidth
    case screen
    case sheet
    case fixed(CGSize)

    var usesDefaultIOSDevices: Bool {
        switch self {
        case .screen, .sheet:
            return true
        case .intrinsicContentSize, .constrainedWidth, .fixed:
            return false
        }
    }

    var fixedConstrainedWidth: CGFloat? {
        switch self {
        case .constrainedWidth:
            return SnapshotDevice.iPhoneDefault.size.width
        case .intrinsicContentSize, .screen, .sheet, .fixed:
            return nil
        }
    }

    func resolvedSize(
        for configuration: SnapshotImageConfiguration,
        defaultSize: CGSize
    ) -> CGSize? {
        switch self {
        case .intrinsicContentSize, .constrainedWidth:
            return configuration.size
        case .screen, .sheet:
            return configuration.resolvedSize(defaultSize: defaultSize)
        case .fixed(let size):
            return size
        }
    }
}
