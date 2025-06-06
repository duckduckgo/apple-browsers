//
//  AddressBarPermissionButtonsIconsProviding.swift
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
import DesignResourcesKitIcons

protocol AddressBarPermissionButtonsIconsProviding {
    var locationIcon: NSImage { get }
    var locationSolid: NSImage { get }
    var popupsIcon: NSImage { get }
    var externalSchemeIcon: NSImage { get }
}

final class LegacyAddressBarPermissionButtonIconsProvider: AddressBarPermissionButtonsIconsProviding {
    var locationIcon: NSImage { .geolocationIcon }
    var locationSolid: NSImage { .geolocationActive }
    var popupsIcon: NSImage { .popupBlocked }
    var externalSchemeIcon: NSImage { .externalAppScheme }
}

final class CurrentAddressBarPermissionButtonIconsProvider: AddressBarPermissionButtonsIconsProviding {
    var locationIcon: NSImage { DesignSystemImages.Glyphs.Size16.location }
    var locationSolid: NSImage { DesignSystemImages.Glyphs.Size16.locationSolid }
    var popupsIcon: NSImage { DesignSystemImages.Glyphs.Size16.popupBlocked }
    var externalSchemeIcon: NSImage { DesignSystemImages.Glyphs.Size16.openIn }
}
