//
//  HTTPURLResponseExtension.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

public extension HTTPURLResponse {

    var shouldDownload: Bool {
        let contentDisposition = self.allHeaderFields["Content-Disposition"] as? String
        return contentDisposition?.hasPrefix("attachment") ?? false
    }

    static let acceptedStatusCodes = 200..<300

    enum HTTPURLResponseError: Error {
        case invalidStatusCode
    }

    func validateStatusCode<S: Sequence>(statusCode acceptedStatusCodes: S) -> Error? where S.Iterator.Element == Int {
        return acceptedStatusCodes.contains(statusCode) ? nil : HTTPURLResponseError.invalidStatusCode
    }

    func validateStatusCode() -> Error? {
        validateStatusCode(statusCode: Self.acceptedStatusCodes)
    }

    var isSuccessful: Bool {
        validateStatusCode() == nil
    }

}
