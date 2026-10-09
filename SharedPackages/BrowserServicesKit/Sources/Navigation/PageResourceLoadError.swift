//
//  PageResourceLoadError.swift
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
import FoundationExtensions

public enum PageResourceLoadError: Error, Hashable {
    case error(NSError)
    case statusCode(Int)
}

extension PageResourceLoadError {

    /// Returns nil for successful or unclassified errors
    ///
    static func resourceLoadError(from error: NSError?, response: URLResponse?) -> PageResourceLoadError? {
        if let error {
            return .error(error)
        }

        if let response = response as? HTTPURLResponse {
            return resourceLoadError(response: response)
        }

        return nil
    }
}

public extension PageResourceLoadError {

    /// Encodes as `(errorDomain,code)` or `(statusCode,code)`.
    var stringValue: String {
        switch self {
        case .error(let error):
            return "(\(error.domain),\(error.code))"
        case .statusCode(let statusCode):
            return "(statusCode,\(statusCode))"
        }
    }
}

private extension PageResourceLoadError {

    static func resourceLoadError(response: HTTPURLResponse) -> PageResourceLoadError? {
        guard !(200...299).contains(response.statusCode) else {
            return nil
        }

        return .statusCode(response.statusCode)
    }
}
