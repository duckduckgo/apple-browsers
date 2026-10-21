//
//  ForbiddenCertificatesNavigationResponder.swift
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

import CryptoKit
import DDGNavigation
import Foundation
import Security

/// Cancels TLS connections whose certificate chain contains a certificate with a forbidden SPKI SHA-256 hash.
struct ForbiddenCertificatesNavigationResponder: NavigationResponder {

    /// https://groups.google.com/a/mozilla.org/g/dev-security-policy/c/0R3XLJL6FuE/m/0XofdebrAAAJ
    static let cve2026111943: Set<Data> = Set([
        "43bffa19d6ef651451f6841e019931e96f6f2eaeff28ab4b6f1ce4576de2717b",
        "49dd353dc2b919a3770645117d0e60c16115e7d1bc259eefe734b00ea434fe5f",
        "5c0660a2b164910d8ff589c18e14552e9e0ec237dcefe2cb736d41a4811f81a0",
        "63ecefee431d49523bc1136c4e72d0206a477086caf606cd5cf025686c109cf8",
        "92c063d67e8f14db71d288e11266ffdaf69cbf115f7bab14f3bc2f68d25e0e30",
        "e0254c7fcdc265e2f0f8a428dabb75ab4ae039b4872d62f5ee57f0877d5a8a41",
        "ebed6475c2c2d80fcb199f3fe8dd6e6b3ce60b77eb15d4e42c3dec0c6f5b5105",
        "ec4ffa1ad0ac88081314b7aaffef6a91f97cd57291bb5ba686c5415f5eb4f6b6",
    ].compactMap(Data.init(sha256Hex:)))

    private static let evaluationQueue = DispatchQueue(label: "com.duckduckgo.forbidden-certificates", qos: .userInitiated)

    let forbiddenSPKIHashes: Set<Data>

    init(forbiddenSPKIHashes: Set<Data> = cve2026111943) {
        self.forbiddenSPKIHashes = forbiddenSPKIHashes
    }

    func didReceive(_ authenticationChallenge: URLAuthenticationChallenge, for navigation: Navigation?) async -> AuthChallengeDisposition? {
        guard authenticationChallenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = authenticationChallenge.protectionSpace.serverTrust else {
            return .next
        }
        return await decision(for: trust)
    }

    func decision(for trust: SecTrust) async -> AuthChallengeDisposition? {
        // Evaluation builds the full chain, including a trust anchor the server didn't send.
        // The result is ignored: a forbidden chain must be cancelled even when the user would bypass a certificate error.
        await withCheckedContinuation { continuation in
            // Evaluation may fetch revocation data over the network, so keep it off the main thread.
            // SecTrustEvaluateAsyncWithError must be called on the queue it calls back on.
            Self.evaluationQueue.async {
                let status = SecTrustEvaluateAsyncWithError(trust, Self.evaluationQueue) { _, _, _ in
                    continuation.resume()
                }
                if status != errSecSuccess {
                    continuation.resume()
                }
            }
        }
        let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate] ?? []
        let isForbidden = chain.contains { certificate in
            // A certificate we can't parse is treated as forbidden.
            guard let hash = Self.spkiSHA256(of: certificate) else { return true }
            return forbiddenSPKIHashes.contains(hash)
        }
        return isForbidden ? .cancel : .next
    }

    /// Same value as OkHttp's `X509Certificate.sha256Hash()`: SHA-256 of the DER-encoded SubjectPublicKeyInfo.
    static func spkiSHA256(of certificate: SecCertificate) -> Data? {
        let der = [UInt8](SecCertificateCopyData(certificate) as Data)
        var root = DERReader(der, der.indices)
        guard let certificate = root.next(tag: 0x30) else { return nil }
        var body = DERReader(der, certificate.content)
        guard let tbs = body.next(tag: 0x30) else { return nil }

        var fields = DERReader(der, tbs.content)
        var field = fields.next()
        if field?.tag == 0xA0 { field = fields.next() } // version
        // serialNumber, signature, issuer, validity, subject, subjectPublicKeyInfo
        for _ in 0..<5 { field = fields.next() }

        guard let spki = field, spki.tag == 0x30 else { return nil }
        return Data(SHA256.hash(data: der[spki.element]))
    }
}

private struct DERReader {
    struct Element {
        let tag: UInt8
        let content: Range<Int>
        let element: Range<Int>
    }

    private let bytes: [UInt8]
    private var offset: Int
    private let end: Int

    init(_ bytes: [UInt8], _ range: Range<Int>) {
        self.bytes = bytes
        self.offset = range.lowerBound
        self.end = range.upperBound
    }

    mutating func next(tag expectedTag: UInt8) -> Element? {
        guard let element = next(), element.tag == expectedTag else { return nil }
        return element
    }

    mutating func next() -> Element? {
        let start = offset
        guard offset + 2 <= end else { return nil }
        let tag = bytes[offset]
        var length = Int(bytes[offset + 1])
        offset += 2
        if length & 0x80 != 0 {
            let count = length & 0x7F
            guard (1...4).contains(count), offset + count <= end else { return nil }
            length = bytes[offset..<offset + count].reduce(0) { $0 << 8 | Int($1) }
            offset += count
        }
        guard length <= end - offset else { return nil }
        let content = offset..<offset + length
        offset += length
        return Element(tag: tag, content: content, element: start..<offset)
    }
}

private extension Data {
    init?(sha256Hex hex: String) {
        guard hex.utf8.count == SHA256.byteCount * 2 else { return nil }
        var bytes = [UInt8]()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }
}
