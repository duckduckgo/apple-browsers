//
//  BWEncryption.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import CryptoKit
import CommonCrypto

enum BWEncryptionError: Error {
    case keyGenerationFailed
    case invalidSharedKeySize
    case decryptionFailed
    case encryptionFailed
    case invalidData
    case cryptographicFailure(String)
}

final class BWEncryption {

    private static let keyLength = 2048
    private static let publicExponent = 65537
    private static let ivLength = 16
    private static let blockSize = 16
    private static let sharedKeySize = 64

    // RSA key pair for shared key encryption/decryption
    private var privateKey: SecKey?
    private var publicKey: SecKey?

    // Shared key components
    private var sharedKeyData: Data?
    private var encryptionKey: Data?
    private var macKey: Data?

    // MARK: - Public Methods

    func generateKeys() -> String? {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: Self.keyLength,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: false
            ],
            kSecPublicKeyAttrs as String: [
                kSecAttrIsPermanent as String: false
            ]
        ]

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            if let error = error?.takeRetainedValue() {
                print("Key generation failed: \(error)")
            }
            return nil
        }

        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            return nil
        }

        self.privateKey = privateKey
        self.publicKey = publicKey

        // Export public key in DER format (compatible with OpenSSL format)
        var exportError: Unmanaged<CFError>?
        guard let rawPublicKeyData = SecKeyCopyExternalRepresentation(publicKey, &exportError) as Data? else {
            if let error = exportError?.takeRetainedValue() {
                print("Public key export failed: \(error)")
            }
            return nil
        }

        // Convert raw key data to DER-encoded SubjectPublicKeyInfo format (same as OpenSSL i2d_RSA_PUBKEY_bio)
        guard let derEncodedKey = createDEREncodedRSAPublicKey(from: rawPublicKeyData) else {
            print("Failed to create DER-encoded public key")
            return nil
        }

        return derEncodedKey.base64EncodedString()
    }

    @discardableResult
    func setSharedKey(_ sharedKey: Data) -> Bool {
        guard sharedKey.count == Self.sharedKeySize else {
            return false
        }

        self.sharedKeyData = sharedKey
        // First 32 bytes are encryption/decryption key
        self.encryptionKey = sharedKey.subdata(in: 0..<32)
        // Last 32 bytes are HMAC key
        self.macKey = sharedKey.subdata(in: 32..<64)

        return true
    }

    func decryptSharedKey(_ encryptedSharedKey: String) -> String? {
        guard let privateKey = self.privateKey else { return nil }

        cleanKeyData()

        guard let encryptedData = Data(base64Encoded: encryptedSharedKey) else {
            return nil
        }

        // Decrypt using RSA private key with OAEP padding
        var error: Unmanaged<CFError>?
        guard let decryptedData = SecKeyCreateDecryptedData(
            privateKey,
            .rsaEncryptionOAEPSHA1,
            encryptedData as CFData,
            &error
        ) as Data? else {
            if let error = error?.takeRetainedValue() {
                print("RSA decryption failed: \(error)")
            }
            return nil
        }

        // Set the shared key for future operations
        guard setSharedKey(decryptedData) else {
            return nil
        }

        return decryptedData.base64EncodedString()
    }

    func encryptData(_ data: Data) -> BWEncryptionOutput? {
        guard let encryptionKey = self.encryptionKey,
              let macKey = self.macKey else {
            return nil
        }

        // Generate random IV
        guard let ivData = generateIV() else {
            return nil
        }

        // Encrypt using AES-CBC with CommonCrypto
        guard let encryptedData = encryptAESCBC(data: data, key: encryptionKey, iv: ivData) else {
            print("AES encryption failed")
            return nil
        }

        // Compute HMAC
        let hmacData = computeHMAC(data: encryptedData, iv: ivData, key: macKey)

        return BWEncryptionOutput(iv: ivData, data: encryptedData, hmac: hmacData)
    }

    func decryptData(_ data: Data, andIv ivData: Data) -> Data {
        guard let encryptionKey = self.encryptionKey else {
            return Data()
        }

        guard let decryptedData = decryptAESCBC(data: data, key: encryptionKey, iv: ivData) else {
            print("AES decryption failed")
            return Data()
        }

        return decryptedData
    }

    func computeHmac(_ data: Data, iv: Data) -> Data {
        guard let macKey = self.macKey else {
            return Data()
        }
        return computeHMAC(data: data, iv: iv, key: macKey)
    }

    func cleanKeys() {
        privateKey = nil
        publicKey = nil
        cleanKeyData()
    }

    // MARK: - Private Methods

    private func generateIV() -> Data? {
        var ivData = Data(count: Self.ivLength)
        let result = ivData.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, Self.ivLength, bytes.bindMemory(to: UInt8.self).baseAddress!)
        }

        guard result == errSecSuccess else {
            return nil
        }

        return ivData
    }

    private func computeHMAC(data: Data, iv: Data, key: Data) -> Data {
        var macData = Data()
        macData.append(iv)
        macData.append(data)

        let symmetricKey = SymmetricKey(data: key)
        let hmac: HMAC<SHA256>.MAC = HMAC.authenticationCode(for: macData, using: symmetricKey)
        return Data(hmac)
    }

    private func cleanKeyData() {
        sharedKeyData = nil
        encryptionKey = nil
        macKey = nil
    }

    private func encryptAESCBC(data: Data, key: Data, iv: Data) -> Data? {
        guard key.count == 32 else {
            print("Invalid key size: \(key.count), expected 32 bytes for AES-256")
            return nil
        }

        // Manual padding to match legacy implementation
        // AES block size is 16 bytes, pad data to next block boundary
        let blockSize = 16
        let paddedLength = ((data.count / blockSize) + 1) * blockSize
        var paddedData = Data(data)
        paddedData.append(Data(count: paddedLength - data.count))

        let keyBytes = key.withUnsafeBytes { $0.bindMemory(to: UInt8.self) }
        let paddedDataBytes = paddedData.withUnsafeBytes { $0.bindMemory(to: UInt8.self) }
        let ivBytes = iv.withUnsafeBytes { $0.bindMemory(to: UInt8.self) }

        let bufferSize = paddedData.count
        var buffer = Data(count: bufferSize)
        var numBytesEncrypted: size_t = 0

        let status = buffer.withUnsafeMutableBytes { bufferBytes in
            CCCrypt(
                CCOperation(kCCEncrypt),
                CCAlgorithm(kCCAlgorithmAES),
                CCOptions(0),  // No automatic padding - we handle it manually
                keyBytes.baseAddress,
                key.count,  // Key size in bytes (32 for AES-256)
                ivBytes.baseAddress,
                paddedDataBytes.baseAddress,
                paddedData.count,
                bufferBytes.bindMemory(to: UInt8.self).baseAddress,
                bufferSize,
                &numBytesEncrypted
            )
        }

        guard status == kCCSuccess else {
            print("AES encryption failed with status: \(status)")
            return nil
        }

        return buffer.prefix(numBytesEncrypted)
    }

    private func decryptAESCBC(data: Data, key: Data, iv: Data) -> Data? {
        guard key.count == 32 else {
            print("Invalid key size: \(key.count), expected 32 bytes for AES-256")
            return nil
        }

        let keyBytes = key.withUnsafeBytes { $0.bindMemory(to: UInt8.self) }
        let dataBytes = data.withUnsafeBytes { $0.bindMemory(to: UInt8.self) }
        let ivBytes = iv.withUnsafeBytes { $0.bindMemory(to: UInt8.self) }

        let bufferSize = data.count
        var buffer = Data(count: bufferSize)
        var numBytesDecrypted: size_t = 0

        let status = buffer.withUnsafeMutableBytes { bufferBytes in
            CCCrypt(
                CCOperation(kCCDecrypt),
                CCAlgorithm(kCCAlgorithmAES),
                CCOptions(0),  // No automatic padding - we handle it manually
                keyBytes.baseAddress,
                key.count,  // Key size in bytes (32 for AES-256)
                ivBytes.baseAddress,
                dataBytes.baseAddress,
                data.count,
                bufferBytes.bindMemory(to: UInt8.self).baseAddress,
                bufferSize,
                &numBytesDecrypted
            )
        }

        guard status == kCCSuccess else {
            print("AES decryption failed with status: \(status)")
            return nil
        }

        var decryptedData = buffer.prefix(numBytesDecrypted)

        // Remove padding (correctly, unlike the legacy implementation)
        // Find the last non-zero byte to determine original data length
        while decryptedData.count > 0 && decryptedData.last == 0 {
            decryptedData = decryptedData.dropLast()
        }

        return decryptedData
    }

    /// Creates a DER-encoded SubjectPublicKeyInfo structure from raw RSA public key data
    /// This matches the format produced by OpenSSL's i2d_RSA_PUBKEY_bio function
    private func createDEREncodedRSAPublicKey(from rawKeyData: Data) -> Data? {
        // RSA public key algorithm identifier (same as OpenSSL uses)
        let rsaAlgorithmIdentifier: [UInt8] = [
            0x30, 0x0d,  // SEQUENCE, length 13
            0x06, 0x09,  // OBJECT IDENTIFIER, length 9
            0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01,  // RSA encryption OID
            0x05, 0x00   // NULL
        ]

        // Create BIT STRING for the public key
        var publicKeyBitString = Data()
        publicKeyBitString.append(0x03)  // BIT STRING tag

        // Calculate and encode length
        let bitStringContentLength = rawKeyData.count + 1  // +1 for unused bits byte
        if bitStringContentLength < 0x80 {
            publicKeyBitString.append(UInt8(bitStringContentLength))
        } else if bitStringContentLength < 0x100 {
            publicKeyBitString.append(0x81)
            publicKeyBitString.append(UInt8(bitStringContentLength))
        } else {
            publicKeyBitString.append(0x82)
            publicKeyBitString.append(UInt8(bitStringContentLength >> 8))
            publicKeyBitString.append(UInt8(bitStringContentLength & 0xFF))
        }

        publicKeyBitString.append(0x00)  // Number of unused bits
        publicKeyBitString.append(rawKeyData)

        // Create the outer SEQUENCE (SubjectPublicKeyInfo)
        var derData = Data()
        derData.append(0x30)  // SEQUENCE tag

        let totalContentLength = rsaAlgorithmIdentifier.count + publicKeyBitString.count
        if totalContentLength < 0x80 {
            derData.append(UInt8(totalContentLength))
        } else if totalContentLength < 0x100 {
            derData.append(0x81)
            derData.append(UInt8(totalContentLength))
        } else {
            derData.append(0x82)
            derData.append(UInt8(totalContentLength >> 8))
            derData.append(UInt8(totalContentLength & 0xFF))
        }

        derData.append(Data(rsaAlgorithmIdentifier))
        derData.append(publicKeyBitString)

        return derData
    }
}
