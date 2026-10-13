//
//  SyncDeviceTypeImage.swift
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

import DesignResourcesKitIcons
import SwiftUI

struct SyncDeviceTypeImage: View {

    let device: SyncSettingsViewModel.Device

    var body: some View {
        Image(uiImage: image)
    }

    private var image: UIImage {
        if device.isThirdParty {
            return DesignSystemImages.Glyphs.Size24.deviceAll
        }
        switch device.type {
        case "desktop":
            return DesignSystemImages.Glyphs.Size24.deviceDesktop
        case "tablet":
            return DesignSystemImages.Glyphs.Size24.deviceTablet
        default:
            return DesignSystemImages.Glyphs.Size24.deviceMobile
        }
    }
}
