//
//  SSLErrorType.swift
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
import Security
import WebKit

public let SSLErrorCodeKey = "_kCFStreamErrorCodeKey"

public enum SSLErrorType: String, Encodable {

    case expired
    case selfSigned
    case wrongHost
    case invalid

    init(errorCode: Int32) {
        self = switch errorCode {
        case errSSLCertExpired: .expired
        case errSSLXCertChainInvalid: .selfSigned
        case errSSLHostNameMismatch: .wrongHost
        default: .invalid
        }
    }

    public var pixelParameter: String {
        switch self {
        case .expired: return "expired"
        case .wrongHost: return "wrong_host"
        case .selfSigned: return "self_signed"
        case .invalid: return "generic"
        }
    }

}

extension WKError {
    public var sslErrorType: SSLErrorType? {
        _nsError.sslErrorType
    }
}
extension NSError {
    public var sslErrorType: SSLErrorType? {
        // Pre-macOS 26.4 error code detection
        if let code = self.userInfo[SSLErrorCodeKey] as? Int32 {
            return SSLErrorType(errorCode: code)
        }

        // macOS 26.4+: the NSUnderlyingError OSStatus is generic ("bad certificate
        // format", -9808) for every SSL failure, so it can't tell expired from
        // wrong-host from anything else. The peer-trust SecTrustRef in userInfo
        // still knows the specific reason, so evaluate it ourselves.
        if let trustObject = self.userInfo[NSURLErrorFailingURLPeerTrustErrorKey],
           CFGetTypeID(trustObject as CFTypeRef) == SecTrustGetTypeID() {
            // swiftlint:disable:next force_cast
            let trust = trustObject as! SecTrust
            return Self.sslErrorType(from: trust)
        }

        // Last-resort fallback for pre-26.4 builds that lack SSLErrorCodeKey but
        // do have a meaningful underlying OSStatus.
        if let underlyingError = self.userInfo[NSUnderlyingErrorKey] as? NSError {
            return SSLErrorType(errorCode: Int32(underlyingError.code))
        }

        return nil
    }

    /// Determine the SSL failure type by evaluating the peer-trust SecTrustRef
    /// and walking the resulting CFError chain for a specific Security.framework
    /// code. Required on macOS 26.4+ where the OSStatus in NSUnderlyingError no
    /// longer disambiguates between expired / hostname-mismatch / etc.
    private static func sslErrorType(from trust: SecTrust) -> SSLErrorType {
        var cfError: CFError?
        let trusted = SecTrustEvaluateWithError(trust, &cfError)
        guard !trusted, let error = cfError as Error? else { return .invalid }

        // Walk the underlying-error chain looking for a specific Security.framework
        // code. Falls through to .invalid if nothing specific is found.
        var current: NSError? = error as NSError
        while let e = current {
            switch Int32(e.code) {
            case errSecCertificateExpired, errSecCertificateNotValidYet:
                return .expired
            case errSecHostNameMismatch:
                return .wrongHost
            case errSecNotTrusted:
                return .selfSigned
            default:
                break
            }
            current = e.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return .invalid
    }
}
