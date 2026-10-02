//
//  SSLErrorTypeTests.swift
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

import XCTest
import Security
@testable import SpecialErrorPages

/// Regression tests for #4255 ("Improve SSL error handling on macOS 26.4").
///
/// `NSError.sslErrorType` must fall back to the OSStatus carried by `NSUnderlyingError` when the
/// legacy `_kCFStreamErrorCodeKey` is absent, and it must always resolve to a concrete case
/// (defaulting to `.invalid`) rather than `nil` when an underlying SSL error is present. Reverting
/// the `NSUnderlyingErrorKey` fallback makes `sslErrorType` return `nil` for these cases.
final class SSLErrorTypeTests: XCTestCase {

    func testSSLErrorTypeFromNSUnderlyingError_expiredCertificate() {
        let underlying = NSError(domain: NSOSStatusErrorDomain, code: Int(errSSLCertExpired))
        let error = NSError(domain: NSURLErrorDomain,
                            code: NSURLErrorServerCertificateUntrusted,
                            userInfo: [NSUnderlyingErrorKey: underlying])

        XCTAssertEqual(error.sslErrorType, .expired)
    }

    func testSSLErrorTypeFromNSUnderlyingError_hostNameMismatch() {
        let underlying = NSError(domain: NSOSStatusErrorDomain, code: Int(errSSLHostNameMismatch))
        let error = NSError(domain: NSURLErrorDomain,
                            code: NSURLErrorServerCertificateUntrusted,
                            userInfo: [NSUnderlyingErrorKey: underlying])

        XCTAssertEqual(error.sslErrorType, .wrongHost)
    }

    func testSSLErrorTypeFromNSUnderlyingError_unrecognisedCodeFallsBackToInvalid() {
        // An underlying error whose OSStatus isn't a recognised SSL code must still resolve — to
        // `.invalid`, not `nil` — exercising both the NSUnderlyingErrorKey fallback and the default.
        let underlying = NSError(domain: NSOSStatusErrorDomain, code: -1)
        let error = NSError(domain: NSURLErrorDomain,
                            code: NSURLErrorServerCertificateUntrusted,
                            userInfo: [NSUnderlyingErrorKey: underlying])

        XCTAssertEqual(error.sslErrorType, .invalid)
    }

    func testSSLErrorTypeFromLegacyStreamErrorCodeKeyStillResolves() {
        // The pre-26.4 detection path must remain intact.
        let error = NSError(domain: NSURLErrorDomain,
                            code: NSURLErrorSecureConnectionFailed,
                            userInfo: [SSLErrorCodeKey: Int32(errSSLXCertChainInvalid)])

        XCTAssertEqual(error.sslErrorType, .selfSigned)
    }

    func testSSLErrorTypeWithNoRecognisedKeysReturnsNil() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorUnknown, userInfo: [:])

        XCTAssertNil(error.sslErrorType)
    }
}
