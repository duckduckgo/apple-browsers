//
//  URL+SuggestionDisplay.swift
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

import Core
import Foundation

extension URL {

    /// Renders a URL the way it is shown in autocomplete / Duck.ai suggestion rows:
    /// strips http(s) scheme + www prefix and any trailing slash on the bare host.
    func formattedForSuggestion() -> String {
        let string = absoluteString
            .dropping(prefix: "https://")
            .dropping(prefix: "http://")
            .droppingWwwPrefix()
        return pathComponents.isEmpty ? string : string.dropping(suffix: "/")
    }
}
