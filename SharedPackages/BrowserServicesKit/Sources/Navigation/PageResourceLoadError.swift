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

public enum PageResourceLoadError: String, Error, Hashable {
    case dns
    case certificate
    case connection
    case client     /// HTTP 4xx
    case server     /// HTTP 5xx
}

extension PageResourceLoadError {

    /// Returns nil for successful or unclassified errors
    ///
    static func resourceLoadError(from error: NSError?, response: URLResponse?) -> PageResourceLoadError? {
        if let error {
            return resourceLoadError(from: error)
        }

        if let response = response as? HTTPURLResponse {
            return resourceLoadError(response: response)
        }

        return nil
    }
}

private extension PageResourceLoadError {

    static func resourceLoadError(from error: NSError) -> PageResourceLoadError? {
        guard error.domain == NSURLErrorDomain else {
            return nil
        }

        switch URLError.Code(rawValue: error.code) {
        case .cannotFindHost,
                .dnsLookupFailed:
            return .dns
        case .cannotConnectToHost,
                .timedOut,
                .networkConnectionLost,
                .notConnectedToInternet,
                .dataNotAllowed,
                .internationalRoamingOff:
            return .connection
        case .secureConnectionFailed,
                .serverCertificateHasBadDate,
                .serverCertificateUntrusted,
                .serverCertificateHasUnknownRoot,
                .serverCertificateNotYetValid,
                .clientCertificateRejected,
                .clientCertificateRequired:
            return .certificate
        default:
            return nil
        }
    }

    static func resourceLoadError(response: HTTPURLResponse) -> PageResourceLoadError? {
        switch response.statusCode {
        case 400...499:
            return .client
        case 500...599:
            return .server
        default:
            return nil
        }
    }
}
