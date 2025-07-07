//
//  DownloadsWebViewMock.swift
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

import Foundation
import WebKit

final class DownloadsWebViewMock: WKWebView {
    var startDownloadBlock: (URLRequest) -> NSObject? = { _ in fatalError("Start download block not set") }
    var resumeDownloadBlock: (Data) -> NSObject? = { _ in fatalError("Resume download block not set") }

    override func startDownload(using request: URLRequest, completionHandler: @escaping @MainActor (WKDownload) -> Void) {
        let completionHandler = unsafeBitCast(completionHandler, to: ((NSObject?) -> Void).self)
        completionHandler(startDownloadBlock(request))
    }

    override func resumeDownload(fromResumeData resumeData: Data, completionHandler: @escaping @MainActor (WKDownload) -> Void) {
        let completionHandler = unsafeBitCast(completionHandler, to: ((NSObject?) -> Void).self)
        completionHandler(resumeDownloadBlock(resumeData))
    }
}
