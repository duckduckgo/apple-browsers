//
//  MainResourceDataProviding.swift
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

import Foundation
import WebKit

/// Read access to the bytes of the document a web view is displaying. `WKWebView` conforms per
/// platform (macOS via a private API, iOS via URLSession below).
public protocol MainResourceDataProviding: AnyObject {
    @MainActor func mainResourceData(timeout: TimeInterval) async -> Data?
}

public extension MainResourceDataProviding {
    @MainActor func mainResourceData() async -> Data? {
        await mainResourceData(timeout: 5)
    }
}

#if os(iOS)

extension WKWebView: MainResourceDataProviding {

    public func mainResourceData(timeout: TimeInterval) async -> Data? {
        guard let url, url.scheme == "http" || url.scheme == "https" else { return nil }

        var request = URLRequest(url: url, timeoutInterval: timeout)
        if let userAgent = await browserUserAgent() {
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }

        // Preload the tab's cookies into the ephemeral session's private store so URLSession applies
        // their real domain/path/Secure/host-only rules and nothing leaks to the app-global jar.
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.httpCookieAcceptPolicy = .always
        for cookie in await tabCookies() {
            sessionConfiguration.httpCookieStorage?.setCookie(cookie)
        }

        return await CappedResourceReader(maxBytes: DocumentPageContextProvider.maxDocumentBytes)
            .load(request, configuration: sessionConfiguration)
    }

    private func browserUserAgent() async -> String? {
        if let userAgent = customUserAgent, !userAgent.isEmpty {
            return userAgent
        }
        let result = try? await evaluateJavaScript("navigator.userAgent")
        return result as? String
    }

    private func tabCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            configuration.websiteDataStore.httpCookieStore.getAllCookies { continuation.resume(returning: $0) }
        }
    }
}

/// Downloads a request but cancels once the body crosses `maxBytes`, so a huge document is never
/// buffered whole. Returns the over-cap bytes on overflow (the caller still reports too large), nil on failure.
private final class CappedResourceReader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let maxBytes: Int
    private let lock = NSLock()
    private var buffer = Data()
    private var continuation: CheckedContinuation<Data?, Never>?
    private var session: URLSession?

    init(maxBytes: Int) {
        self.maxBytes = maxBytes
    }

    func load(_ request: URLRequest, configuration: URLSessionConfiguration) async -> Data? {
        await withCheckedContinuation { continuation in
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            lock.lock()
            self.continuation = continuation
            self.session = session
            lock.unlock()
            session.dataTask(with: request).resume()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        buffer.append(data)
        let overCap = buffer.count > maxBytes
        lock.unlock()
        if overCap {
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let result: Data?
        if let urlError = error as? URLError, urlError.code == .cancelled, buffer.count > maxBytes {
            result = buffer
        } else if error != nil {
            result = nil
        } else {
            result = buffer
        }
        let continuation = self.continuation
        self.continuation = nil
        self.session = nil
        lock.unlock()
        session.finishTasksAndInvalidate()
        continuation?.resume(returning: result)
    }
}

#endif
