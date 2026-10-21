//
//  ForbiddenCertificatesNavigationResponderTests.swift
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

import DDGNavigation
import Security
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class ForbiddenCertificatesNavigationResponderTests: XCTestCase {

    // Throwaway P-256 root CA and a leaf for "forbidden.example" it signed, both valid until 2126.
    static let rootDERBase64 = "MIIBnDCCAUKgAwIBAgIUIWobxi/CZRHAt3FLIY8+DJiAhdEwCgYIKoZIzj0EAwIwKzEpMCcGA1UEAwwgRm9yYmlkZGVuIENlcnRpZmljYXRlcyBUZXN0IFJvb3QwIBcNMjYxMDIxMTA1OTA1WhgPMjEyNjA5MjcxMDU5MDVaMCsxKTAnBgNVBAMMIEZvcmJpZGRlbiBDZXJ0aWZpY2F0ZXMgVGVzdCBSb290MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEMapKYhwa70yr4ElsARIEMPlXVY8n6kgM1ICd4GyJd5KSLUE8LJouEfTcZxqjyUuGJkij3nvJ9XwnrnF3qxLZ/aNCMEAwHQYDVR0OBBYEFOBPnNlQZ5Rye+VgbyZDbebbXxA+MA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMCA0gAMEUCIQDoVSqUHHomNg+1jknvgI96V3zKIVJO/lt/0bDXRN9+CAIgQEFWK5op98zO7090RoWae05EjthryCL7gPlGMdTRhSw="
    static let leafDERBase64 = "MIIBmzCCAUGgAwIBAgIUdJX6m40YsGBIozT1wSC4wBy7s08wCgYIKoZIzj0EAwIwKzEpMCcGA1UEAwwgRm9yYmlkZGVuIENlcnRpZmljYXRlcyBUZXN0IFJvb3QwIBcNMjYxMDIxMTA1OTA1WhgPMjEyNjA5MjcxMDU5MDVaMBwxGjAYBgNVBAMMEWZvcmJpZGRlbi5leGFtcGxlMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEo2lr+F7fe0gjSqX5uNIcrS1dRKUyRErVUhmi8QOigVN9/0THzkURyrG9nAF01JHS/eEdQnx0510OynUBKwahh6NQME4wHAYDVR0RBBUwE4IRZm9yYmlkZGVuLmV4YW1wbGUwCQYDVR0TBAIwADATBgNVHSUEDDAKBggrBgEFBQcDATAOBgNVHQ8BAf8EBAMCB4AwCgYIKoZIzj0EAwIDSAAwRQIgLM5MYZIN2d9MMjoShpqIq8QcH1L2LYSWrYLiTDfY+IACIQC9P5OnSogiOgRBxGAu3psbLPjPEUEvhf+RZ6IknaIHAQ=="

    // `openssl x509 -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256`
    static let rootSPKIHex = "0fc4e75424e2d70e19290057ee7fe87585d2e485c0cdce6cc04cec5763868a10"
    static let leafSPKIHex = "fa6578b3d49908efd948c8d61b3a8f7143f7a1e840eb5a15d231cb95354e5371"
    static let unrelatedSPKIHex = "43bffa19d6ef651451f6841e019931e96f6f2eaeff28ab4b6f1ce4576de2717b"

    var root: SecCertificate!
    var leaf: SecCertificate!

    override func setUpWithError() throws {
        root = try XCTUnwrap(SecCertificateCreateWithData(nil, try XCTUnwrap(Data(base64Encoded: Self.rootDERBase64)) as CFData))
        leaf = try XCTUnwrap(SecCertificateCreateWithData(nil, try XCTUnwrap(Data(base64Encoded: Self.leafDERBase64)) as CFData))
    }

    override func tearDown() {
        root = nil
        leaf = nil
    }

    func testSPKIHashMatchesOpenSSL() {
        XCTAssertEqual(ForbiddenCertificatesNavigationResponder.spkiSHA256(of: leaf).map(hex), Self.leafSPKIHex)
        XCTAssertEqual(ForbiddenCertificatesNavigationResponder.spkiSHA256(of: root).map(hex), Self.rootSPKIHex)
    }

    func testDefaultDenylistContainsAllCVEHashes() {
        let hashes = ForbiddenCertificatesNavigationResponder.cve2026111943
        XCTAssertEqual(hashes.count, 8)
        XCTAssertTrue(hashes.allSatisfy { $0.count == 32 })
        XCTAssertTrue(hashes.map(hex).contains(Self.unrelatedSPKIHex))
    }

    func testWhenRootIsForbidden_ThenChallengeIsCancelled() async throws {
        let responder = ForbiddenCertificatesNavigationResponder(forbiddenSPKIHashes: [try data(Self.rootSPKIHex)])
        let disposition = await responder.decision(for: try trust(anchored: true))
        XCTAssertTrue(disposition.isCancel, "\(String(describing: disposition))")
    }

    func testWhenLeafIsForbidden_ThenChallengeIsCancelled() async throws {
        let responder = ForbiddenCertificatesNavigationResponder(forbiddenSPKIHashes: [try data(Self.leafSPKIHex)])
        let disposition = await responder.decision(for: try trust(anchored: true))
        XCTAssertTrue(disposition.isCancel, "\(String(describing: disposition))")
    }

    func testWhenNoCertificateIsForbidden_ThenChallengeIsPassedToNextResponder() async throws {
        let emptyDenylist = ForbiddenCertificatesNavigationResponder(forbiddenSPKIHashes: [])
        let unrelatedDenylist = ForbiddenCertificatesNavigationResponder(forbiddenSPKIHashes: [try data(Self.unrelatedSPKIHex)])

        let emptyDisposition = await emptyDenylist.decision(for: try trust(anchored: true))
        let unrelatedDisposition = await unrelatedDenylist.decision(for: try trust(anchored: true))

        XCTAssertNil(emptyDisposition)
        XCTAssertNil(unrelatedDisposition)
    }

    func testWhenTrustFailsEvaluation_AndChainIsForbidden_ThenChallengeIsCancelled() async throws {
        let untrusted = try trust(anchored: false)
        XCTAssertFalse(SecTrustEvaluateWithError(untrusted, nil), "the root must not be trusted without anchors")

        let responder = ForbiddenCertificatesNavigationResponder(forbiddenSPKIHashes: [try data(Self.rootSPKIHex)])
        let disposition = await responder.decision(for: try trust(anchored: false))
        XCTAssertTrue(disposition.isCancel, "\(String(describing: disposition))")
    }

    func testWhenChallengeIsNotServerTrust_ThenChallengeIsPassedToNextResponder() async throws {
        let responder = ForbiddenCertificatesNavigationResponder(forbiddenSPKIHashes: [try data(Self.rootSPKIHex)])
        let protectionSpace = URLProtectionSpace(host: "forbidden.example", port: 443, protocol: "https", realm: nil, authenticationMethod: NSURLAuthenticationMethodHTTPBasic)
        let challenge = URLAuthenticationChallenge(protectionSpace: protectionSpace, proposedCredential: nil, previousFailureCount: 0, failureResponse: nil, error: nil, sender: ChallangeSender())

        let disposition = await responder.didReceive(challenge, for: nil)
        XCTAssertNil(disposition)
    }

    // MARK: - Helpers

    private func trust(anchored: Bool) throws -> SecTrust {
        var trust: SecTrust?
        XCTAssertEqual(SecTrustCreateWithCertificates([leaf, root] as CFArray, SecPolicyCreateSSL(true, "forbidden.example" as CFString), &trust), errSecSuccess)
        let result = try XCTUnwrap(trust)
        if anchored {
            XCTAssertEqual(SecTrustSetAnchorCertificates(result, [root] as CFArray), errSecSuccess)
        }
        return result
    }

    private func data(_ hex: String) throws -> Data {
        var bytes = [UInt8]()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            bytes.append(try XCTUnwrap(UInt8(hex[index..<next], radix: 16)))
            index = next
        }
        return Data(bytes)
    }

    private func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}

private extension Optional where Wrapped == AuthChallengeDisposition {
    var isCancel: Bool {
        if case .cancel = self { return true }
        return false
    }
}
