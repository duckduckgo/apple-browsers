//
//  APIHeaders.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

public extension APIRequest {

    struct Headers {

        public typealias UserAgent = String
        public private(set) static var userAgent: UserAgent?
        public static func setUserAgent(_ userAgent: UserAgent) {
            self.userAgent = userAgent
        }

        let userAgent: UserAgent
        let acceptEncoding: String = "gzip;q=1.0, compress;q=0.5"
        let acceptLanguage: String = {
            let languages = Locale.preferredLanguages.prefix(6)
            return languages.enumerated().map { index, language in
                let q = 1.0 - (Double(index) * 0.1)
                return "\(language);q=\(q)"
            }.joined(separator: ", ")
        }()
        let etag: String?
        let additionalHeaders: HTTPHeaders?

        public init(userAgent: UserAgent? = nil, etag: String? = nil, additionalHeaders: HTTPHeaders? = nil) {
            self.userAgent = userAgent ?? Self.userAgent ?? ""
            self.etag = etag
            self.additionalHeaders = additionalHeaders
        }

        public var httpHeaders: HTTPHeaders {
            var headers = [
                HTTPHeaderKey.acceptEncoding: acceptEncoding,
                HTTPHeaderKey.acceptLanguage: acceptLanguage,
                HTTPHeaderKey.userAgent: userAgent
            ]
            if let etag {
                headers[HTTPHeaderKey.ifNoneMatch] = etag
            }
            if let additionalHeaders {
                headers.merge(additionalHeaders) { old, _ in old }
            }
            return headers
        }

    }

}
