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

// swiftlint:disable as_nserror

extension NSError {

    /// Copies `error` into a real `NSError` without Swift's `Error` -> `NSError` bridging.
    ///
    /// WebKit vends Web Extension errors as `WKNSError`, an `NSProxy` posing as `NSError`. On x86_64 the bridge
    /// (`error as NSError`) mistakes the proxy for an uninitialized Swift error and overwrites it in place, so the
    /// next message sent to it crashes. `as AnyObject` and a class cast leave the proxy intact.
    convenience init(copying error: Error) {
        self.init(copyingObject: error as AnyObject)
    }

    /// The `NSUnderlyingErrorKey` error, if any.
    var underlyingError: NSError? {
        userInfo[NSUnderlyingErrorKey] as? NSError
    }

    private convenience init(copyingObject object: AnyObject) {
        let source = object as! NSError // swiftlint:disable:this force_cast
        var userInfo = source.userInfo
        if let underlying = source.underlyingError {
            userInfo[NSUnderlyingErrorKey] = NSError(copyingObject: underlying)
        }
        self.init(domain: source.domain, code: source.code, userInfo: userInfo)
    }

}

// swiftlint:enable as_nserror
