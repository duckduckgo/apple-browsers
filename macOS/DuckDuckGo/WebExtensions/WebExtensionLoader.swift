//
//  WebExtensionLoader.swift
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

@available(macOS 15.3, *)
protocol WebExtensionLoading: AnyObject {

    func loadWebExtensions(from paths: [String]) -> [WKWebExtension]

}

@available(macOS 15.3, *)
final class WebExtensionLoader: WebExtensionLoading {

    private func loadWebExtension(path: String) -> WKWebExtension? {
        guard let extensionURL = URL(string: path) else {
            assertionFailure("Failed to create URL from path: \(path)")
            return nil
        }
        let webExtension = try? WKWebExtension(resourceBaseURL: extensionURL)
        return webExtension
    }

    func loadWebExtensions(from paths: [String]) -> [WKWebExtension] {
        var result = [WKWebExtension]()
        for webExtensionPath in paths {
            guard let webExtension = loadWebExtension(path: webExtensionPath) else {
                assertionFailure("Failed to load the web extension: \(webExtensionPath)")
                continue
            }

            result.append(webExtension)
        }

        return result
    }

}
