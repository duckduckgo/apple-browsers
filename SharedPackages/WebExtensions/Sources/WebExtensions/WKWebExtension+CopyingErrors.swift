//
//  WKWebExtension+CopyingErrors.swift
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

// WebKit throws `WKNSError` proxies from these APIs, which crash on x86_64
// when bridged to Swift `Error`, even implicitly by `localizedDescription`
// (see NSError+Copying.swift). Each wrapper rethrows a real `NSError`; the
// `wknserror_webkit_calls` SwiftLint rule bans calling the APIs directly.

@available(macOS 15.4, iOS 18.4, *)
extension WKWebExtension {

    /// `WKWebExtension(resourceBaseURL:)`, rethrowing a real `NSError`.
    static func makeCopyingErrors(
        at resourceBaseURL: URL
    ) async throws -> WKWebExtension {
        do {
            return try await WKWebExtension(resourceBaseURL: resourceBaseURL)
        } catch {
            throw NSError.webKitSafe(error)
        }
    }

}

@available(macOS 15.4, iOS 18.4, *)
extension WKWebExtensionController {

    func loadCopyingErrors(_ context: WKWebExtensionContext) throws {
        do {
            try load(context)
        } catch {
            throw NSError.webKitSafe(error)
        }
    }

    func unloadCopyingErrors(_ context: WKWebExtensionContext) throws {
        do {
            try unload(context)
        } catch {
            throw NSError.webKitSafe(error)
        }
    }

}

@available(macOS 15.4, iOS 18.4, *)
extension WKWebExtensionContext {

    func loadBackgroundContentCopyingErrors() async throws {
        do {
            try await loadBackgroundContent()
        } catch {
            throw NSError.webKitSafe(error)
        }
    }

}
