//
//  AIChatTabOpener.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

protocol AIChatTabOpening {
    @MainActor
    func openChatTab(_ query: String?)
}

extension AIChatTabOpening {
    @MainActor
    func openChatTab() {
        openChatTab(nil)
    }
}

struct AIChatTabOpener: AIChatTabOpening {

    struct QueryParameters {
        static let queryKey = "q"
        static let autoSendKey = "prompt"
        static let autoSendValue = "1"
        static let systemKey = "duckai"
        static let systemValue = "4"
    }


    @MainActor
    static func openAIChatTab(_ query: String? = nil) {
        var queryURL = AIChatRemoteSettings().aiChatURL

        if let query = query {
            let urlQuery = URLQueryItem(name: QueryParameters.queryKey, value: query)
            queryURL = queryURL.addingOrReplacing(urlQuery)

            let autoSendQuery = URLQueryItem(name: QueryParameters.autoSendKey, value: QueryParameters.autoSendValue)
            queryURL = queryURL.addingOrReplacing(autoSendQuery)

            /// We use duckai=2 on macOS, but this ignores the auto-send and prompt query
            /// Changing this to duckai=4 to simulate iOS
            let changeOSQuery = URLQueryItem(name: QueryParameters.systemKey, value: QueryParameters.systemValue)
            queryURL = queryURL.addingOrReplacing(changeOSQuery)
        }

        WindowControllersManager.shared.showTab(with: .url(queryURL, credential: nil, source: .ui))
    }

    @MainActor
    func openChatTab(_ query: String?) {
        AIChatTabOpener.openAIChatTab(query)
    }
}

extension URL {

    func addingOrReplacing(_ queryItem: URLQueryItem) -> URL {
        guard let queryValue = queryItem.value,
              !queryValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return self
        }

        var components = URLComponents(url: self, resolvingAgainstBaseURL: false)

        var queryItems = components?.queryItems ?? []
        queryItems.removeAll { $0.name == queryItem.name }
        queryItems.append(queryItem)
        components?.queryItems = queryItems

        return components?.url ?? self
    }
}
