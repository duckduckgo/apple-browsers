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

import WebKit

extension TabViewController {

    @MainActor
    public func executeScript(_ javaScriptString: String,
                              args: [String: Any] = [:]) async -> Result<Any?, any Error> {
        do {
            let result = try await webView.callAsyncJavaScript(
                javaScriptString,
                arguments: args,
                in: nil,
                contentWorld: .page
            )
            return .success(result)
        } catch {
            let nsError = error as NSError
            if nsError.domain == "WKErrorDomain",
               let jsMessage = nsError.userInfo["WKJavaScriptExceptionMessage"] as? String {
                let line = nsError.userInfo["WKJavaScriptExceptionLineNumber"] as? Int
                let col = nsError.userInfo["WKJavaScriptExceptionColumnNumber"] as? Int
                let detail = "JS: \(jsMessage) (line:\(line ?? 0) col:\(col ?? 0))"
                return .failure(NSError(domain: "WebDriverJS", code: nsError.code, userInfo: [NSLocalizedDescriptionKey: detail]))
            }
            return .failure(error)
        }
    }

}
