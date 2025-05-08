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

protocol AddressBarIconsProviding {
    var cookiesIcon: NSImage { get }
    var cookiesBiteIcon: NSImage { get }
    var addBookmarkIcon: NSImage { get }
    var bookmarkFilledIcon: NSImage { get }
}

final class LegacyAddressBarIconsProvider: AddressBarIconsProviding {
    let cookiesIcon: NSImage = .cookie
    let cookiesBiteIcon: NSImage = .cookieBite
    let addBookmarkIcon: NSImage = .bookmark
    let bookmarkFilledIcon: NSImage = .bookmarkFilled
}

final class NewAddressBarIconsProvider: AddressBarIconsProviding {
    let cookiesIcon: NSImage = .cookieNew
    let cookiesBiteIcon: NSImage = .cookieBiteNew
    let addBookmarkIcon: NSImage = .addBookmarkNew
    let bookmarkFilledIcon: NSImage = .bookmarkFilledNew
}
