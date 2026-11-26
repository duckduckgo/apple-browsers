//
//  URL+PixelKit.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

import Foundation

extension URL {

    static let pixelBase = ProcessInfo.processInfo.environment["PIXEL_BASE_URL", default: "https://improving.duckduckgo.com"]

    /// Characters a pixel name may keep as-is in the URL path. Everything else, including `/`, is percent-encoded,
    /// so a name always stays a single path segment.
    private static let pixelNameAllowedCharacters: CharacterSet = {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return allowed
    }()

    public static func pixelUrl(forPixelNamed pixelName: String) -> URL {
        // Pixel names can include values from outside the app (for example a key sent by a web page).
        // Before iOS 17 / macOS 14, `URL(string:)` returns nil for characters such as spaces, so the name is
        // percent-encoded first. Names that are already URL-safe are unchanged.
        let encodedName = pixelName.addingPercentEncoding(withAllowedCharacters: pixelNameAllowedCharacters) ?? ""
        let urlString = "\(Self.pixelBase)/t/\(encodedName)"
        return URL(string: urlString)!
    }

}
