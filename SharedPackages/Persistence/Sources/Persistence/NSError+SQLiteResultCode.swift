//
//  NSError+SQLiteResultCode.swift
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

import CoreData
import Foundation

extension NSError {

    /// Returns a copy of this error whose `NSUnderlyingError` is an `NSSQLiteErrorDomain` error carrying the
    /// SQLite result code found in `userInfo[NSSQLiteErrorDomain]`. The rest of `userInfo` is kept unchanged.
    ///
    /// Returns `self` when `userInfo` has no SQLite result code, or when the error already has an underlying error.
    func unpackingSQLiteResultCode() -> NSError {
        guard userInfo[NSUnderlyingErrorKey] == nil,
              let resultCode = userInfo[NSSQLiteErrorDomain] as? NSNumber else {
            return self
        }

        var unpackedUserInfo = userInfo
        unpackedUserInfo[NSUnderlyingErrorKey] = NSError(domain: NSSQLiteErrorDomain, code: resultCode.intValue)
        return NSError(domain: domain, code: code, userInfo: unpackedUserInfo)
    }
}
