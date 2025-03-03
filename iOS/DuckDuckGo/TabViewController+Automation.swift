//
//  TabViewController+Automation.swift
//  DuckDuckGo
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

extension TabViewController {

    @MainActor
    public func executeScript(_ javaScriptString: String,
                              args: [String: Any] = [:]) async -> Result<Any?, any Error> {
        do {
            var modifiedJavaScriptString = javaScriptString
            // DEBUG
            if javaScriptString.contains("window.__wptrunner_url") {
                modifiedJavaScriptString = """
                function getDocumentHTML() {
                    return new Promise((resolve) => {
                        if (document.readyState === "complete" || document.readyState === "interactive") {
                        // Document is already ready, resolve immediately
                        resolve(document.documentElement.innerHTML);
                        } else {
                        // Wait for the DOM to be fully loaded
                        document.addEventListener("DOMContentLoaded", () => {
                            resolve(document.documentElement.innerHTML);
                        });
                        }
                    });
                    }
                return getDocumentHTML();
                """
            }
            var result = try await webView.callAsyncJavaScript(
                modifiedJavaScriptString,
                arguments: args,
                in: nil,
                contentWorld: .page
            )
            return .success(result)
        } catch {
            return .failure(error)
        }
    }

}
