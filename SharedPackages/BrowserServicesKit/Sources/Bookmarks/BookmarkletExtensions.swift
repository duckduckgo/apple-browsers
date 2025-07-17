//
//  BookmarkletExtensions.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

// MARK: - String

public extension String {
    func isBookmarklet() -> Bool {
        return self.lowercased().hasPrefix("javascript:")
    }

    func toDecodedBookmarklet() -> String? {
        guard self.isBookmarklet(),
              let result = self.dropping(prefix: "javascript:").removingPercentEncoding,
              !result.isEmpty else { return nil }
        return result
    }

    func toEncodedBookmarklet() -> URL? {
        let allowedCharacters = CharacterSet.alphanumerics.union(.urlQueryAllowed)
        guard self.isBookmarklet(),
              let encoded = self.dropping(prefix: "javascript:")
                // Avoid double encoding by removing any encoding first
                .removingPercentEncoding?
                .addingPercentEncoding(withAllowedCharacters: allowedCharacters) else { return nil }
        return URL(string: "javascript:\(encoded)")
    }
}

// MARK: - URL

public extension URL {

    func isBookmarklet() -> Bool {
        return absoluteString.isBookmarklet()
    }

    func toDecodedBookmarklet() -> String? {
        return absoluteString.toDecodedBookmarklet()
    }

}
