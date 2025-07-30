//
//  Suggestion+GeneralPixel.swift
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

import PixelKit
import Suggestions

extension Suggestion {

    func autocompletePixel(from source: GeneralPixel.AutocompleteSource) -> GeneralPixel? {
        switch self {
        case .phrase:
            return .autocompleteClickPhrase(from: source)
        case .website:
            return .autocompleteClickWebsite(from: source)
        case .bookmark(_, _, let isFavorite, _):
            return isFavorite ? .autocompleteClickFavorite(from: source) : .autocompleteClickBookmark(from: source)
        case .historyEntry:
            return .autocompleteClickHistory(from: source)
        case .openTab:
            return .autocompleteClickOpenTab(from: source)
        case .internalPage:
            return nil
        case .unknown:
            return nil
        }
    }

}
