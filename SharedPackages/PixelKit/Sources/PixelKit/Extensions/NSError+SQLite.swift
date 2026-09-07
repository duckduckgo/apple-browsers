//
//  NSError+SQLite.swift
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

extension NSError {

    /// The SQLite result codes carried by this error or by any error in its underlying chain,
    /// reported alongside the chain rather than as a link in it.
    ///
    /// Two producers attach the plain result code under different `userInfo` keys:
    /// `SecureStorageError` uses `SQLiteResultCode`, Core Data uses `NSSQLiteErrorDomain`. Both
    /// hold the same kind of value, a SQLite result code rather than an `NSError`, so both map to
    /// `Parameters.underlyingErrorSQLiteCode`.
    ///
    /// The chain is walked outermost first and the first error carrying any SQLite code wins, so
    /// the plain and extended codes always come from the same error and can't be mixed across
    /// producers. Within one error, `SQLiteResultCode` takes precedence.
    var sqliteResultCodeParameters: [String: String] {
        for error in selfAndUnderlyingErrors {
            let parameters = error.ownSQLiteResultCodeParameters
            if !parameters.isEmpty {
                return parameters
            }
        }

        return [:]
    }

    /// The SQLite result codes in this error's own `userInfo`, ignoring its underlying chain.
    private var ownSQLiteResultCodeParameters: [String: String] {
        var parameters = [String: String]()

        if let resultCode = userInfo[SQLiteUserInfoKey.secureStorageResultCode] as? NSNumber
            ?? userInfo[SQLiteUserInfoKey.coreDataResultCode] as? NSNumber {
            parameters[PixelKit.Parameters.underlyingErrorSQLiteCode] = "\(resultCode.intValue)"
        }

        if let extendedResultCode = userInfo[SQLiteUserInfoKey.secureStorageExtendedResultCode] as? NSNumber {
            parameters[PixelKit.Parameters.underlyingErrorSQLiteExtendedCode] = "\(extendedResultCode.intValue)"
        }

        return parameters
    }

    /// This error followed by its `NSUnderlyingError` chain, outermost first, bounded so a cyclic
    /// chain can't spin forever.
    private var selfAndUnderlyingErrors: [NSError] {
        var errors = [NSError]()
        var nextError: NSError? = self

        while let error = nextError, errors.count < Constant.maximumChainDepth {
            errors.append(error)
            nextError = error.userInfo[NSUnderlyingErrorKey] as? NSError
        }

        return errors
    }

    private enum Constant {
        static let maximumChainDepth = 10
    }

    private enum SQLiteUserInfoKey {
        /// Written by `SecureStorageError`.
        static let secureStorageResultCode = "SQLiteResultCode"
        static let secureStorageExtendedResultCode = "SQLiteExtendedResultCode"
        /// Written by Core Data, which reports no extended code.
        static let coreDataResultCode = "NSSQLiteErrorDomain" // Disabled for now
    }
}
