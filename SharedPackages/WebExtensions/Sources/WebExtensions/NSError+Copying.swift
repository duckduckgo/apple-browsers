//
//  NSError+Copying.swift
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

// WebKit vends Web Extension errors as `WKNSError`, an `NSProxy` posing as
// `NSError`. On x86_64, Swift's `Error` -> `NSError` bridge (`as NSError`,
// `localizedDescription`, ...) mistakes the proxy for an uninitialized Swift
// error and overwrites it in place, so the next message sent to it crashes.
// `as AnyObject` and a class cast leave the proxy intact.

extension NSError {

    /// `error` as an `NSError`, without Swift's `Error` -> `NSError` bridge.
    ///
    /// A real `NSError` is returned as is; a `WKNSError` proxy is copied.
    static func webKitSafe(_ error: Error) -> NSError {
        let object = error as AnyObject
        let isRealNSError = object_getClass(object) is NSError.Type
        // A class cast, not the `Error` bridge.
        if isRealNSError, let nsError = object as? NSError {
            return nsError
        }
        return NSError(copyingObject: object)
    }

    /// The `NSUnderlyingErrorKey` error, if any.
    var underlyingError: NSError? {
        userInfo[NSUnderlyingErrorKey] as? NSError
    }

    /// A real `NSError` copy of `object` and its underlying error.
    convenience init(copyingObject object: AnyObject) {
        // A class cast, which the proxy forwards; not the `Error` bridge.
        guard let source = object as? NSError else {
            let description = "Unexpected error object: \(type(of: object))"
            let userInfo = [NSDebugDescriptionErrorKey: description]
            let domain = "WebExtensionsUnexpectedError"
            self.init(domain: domain, code: 0, userInfo: userInfo)
            return
        }
        var userInfo = source.userInfo
        if let underlying = source.underlyingError {
            userInfo[NSUnderlyingErrorKey] = NSError(copyingObject: underlying)
        }
        self.init(domain: source.domain, code: source.code, userInfo: userInfo)
    }

}
