//
//  WKWebView+MainResourceData.swift
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

import ConcurrencyExtensions
import Foundation
import WebKit

/// Read access to the bytes of the document a web view is displaying.
///
/// Exists as a protocol so callers can be unit-tested without the private WebKit API behind the
/// `WKWebView` implementation.
protocol MainResourceDataProviding: AnyObject {
    @MainActor func mainResourceData(timeout: TimeInterval) async -> Data?
}

extension MainResourceDataProviding {
    @MainActor func mainResourceData() async -> Data? {
        await mainResourceData(timeout: 5)
    }
}

@objc private protocol WKWebViewMainResourcePrivate {
    @objc(_getMainResourceDataWithCompletionHandler:)
    func getMainResourceData(completionHandler: @escaping (NSData?, NSError?) -> Void)
}

extension WKWebView: MainResourceDataProviding {

    private static let getMainResourceDataSelector = NSSelectorFromString("_getMainResourceDataWithCompletionHandler:")

    /// The bytes of the currently displayed main-frame document, straight from WebKit — no refetch,
    /// so it also works for documents the page-context user script can't see (PDFs) and for tabs
    /// that aren't in the foreground.
    ///
    /// Returns nil when the runtime doesn't expose the API (it's private) or the call doesn't answer
    /// within `timeout`; callers treat that as "no document context", which is today's behaviour.
    @MainActor
    func mainResourceData(timeout: TimeInterval = 5) async -> Data? {
        guard responds(to: Self.getMainResourceDataSelector) else {
            assertionFailure("WKWebView doesn‘t respond to _getMainResourceDataWithCompletionHandler:")
            return nil
        }
        let webView = unsafeBitCast(self, to: WKWebViewMainResourcePrivate.self)

        let stream = AsyncStream<Data?> { continuation in
            webView.getMainResourceData { data, _ in
                continuation.yield(data as Data?)
                continuation.finish()
            }
        }

        return await withTaskGroup(of: Data?.self) { group in
            group.addTask {
                for await data in stream { return data }
                return nil
            }
            group.addTask {
                try? await Task.sleep(interval: timeout)
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }
}
