//
//  XPCErrorSanitizer.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

struct SanitizedError: CustomNSError {
    let wrappedError: Error
    let underlyingError: Error?

    init(wrappedError: Error, underlyingError: Error?) {
        self.wrappedError = wrappedError
        self.underlyingError = underlyingError
    }

    public var errorUserInfo: [String: Any] {
        let ns = wrappedError as NSError

        var userDictionary: [String: Any] = [
            "OriginalErrorDomain": ns.domain,
            "OriginalErrorCode": ns.code,
            "OriginalErrorDescription": ns.localizedDescription,
        ]

        if let underlyingError = underlyingError as NSError? {
            userDictionary[NSUnderlyingErrorKey] = underlyingError
        }

        return userDictionary
    }
}

public struct XPCErrorSanitizer {

    public static func sanitize(_ error: Error) -> Error {
        let nsError = error as NSError

        guard !XPCErrorSanitizer.isXPCSafe(nsError) else {
            return error
        }

        let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
        return SanitizedError(wrappedError: error, underlyingError: underlyingError?.sanitizedForXPC())
    }

    static func isXPCSafe(_ error: NSError) -> Bool {
        do {
            _ = try NSKeyedArchiver.archivedData(withRootObject: error, requiringSecureCoding: true)
            return true
        } catch {
            return false
        }
    }

}

extension Error {
    func sanitizedForXPC() -> Error {
        return XPCErrorSanitizer.sanitize(self)
    }
}
