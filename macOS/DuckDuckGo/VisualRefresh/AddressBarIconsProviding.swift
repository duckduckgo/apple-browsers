//
//  AddressBarIconsProviding.swift
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

import AppKit
import DesignResourcesKitIcons

protocol AddressBarCookiesIconsProviding {
    var cookiesIcon: NSImage { get }
    var cookiesBiteIcon: NSImage { get }
}

final class LegacyAddressBarCookiesIconsProvider: AddressBarCookiesIconsProviding {
    let cookiesIcon: NSImage = .cookie
    let cookiesBiteIcon: NSImage = .cookieBite
}

final class CurrentAddressBarCookiesIconsProvider: AddressBarCookiesIconsProviding {
    let cookiesIcon: NSImage = DesignSystemImages.Glyphs.Size16.cookieWhole
    let cookiesBiteIcon: NSImage = DesignSystemImages.Glyphs.Size16.cookie
}
