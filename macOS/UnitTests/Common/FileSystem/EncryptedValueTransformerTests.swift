//
//  EncryptedValueTransformerTests.swift
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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

import AppKit
import CryptoKit
import SharedTestUtilities
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class EncryptedValueTransformerTests: XCTestCase {

    func testTransformingValues() {
        let value = "Hello, World"
        let store = MockEncryptionKeyStore(generator: MockEncryptionKeyGenerator(), account: "mock-account")
        let key = try? store.readKey()
        let transformer = EncryptedValueTransformer<NSString>(encryptionKey: key!)
        let transformedValue = transformer.transformedValue(value)

        XCTAssertTrue(transformedValue is Data)
        XCTAssertNotEqual(value.data(using: .utf8), transformedValue as? Data)
    }

    func testReverseTransformingValues() {
        let value = "Hello, World"
        let store = MockEncryptionKeyStore(generator: MockEncryptionKeyGenerator(), account: "mock-account")
        let key = try? store.readKey()
        let transformer = EncryptedValueTransformer<NSString>(encryptionKey: key!)
        let transformedValue = transformer.transformedValue(value)
        let reverseTransformedValue = transformer.reverseTransformedValue(transformedValue)

        XCTAssertTrue(reverseTransformedValue is String)
        XCTAssertEqual(reverseTransformedValue as? String, value)
    }

    // MARK: - Corrupt favicon image must not crash favicon loading

    /// Builds a valid keyed-archive of an `NSImage`, then corrupts the embedded TIFF magic bytes so that
    /// `-[NSBitmapImageRep initWithCoder:]` raises an ObjC `NSInvalidUnarchiveOperationException`
    /// ("Archived bitmap contains bad TIFF data...") on decode – the same failure mode seen in production.
    private func makeCorruptArchivedImageData() throws -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.addRepresentation(rep)

        var data = try NSKeyedArchiver.archivedData(withRootObject: image, requiringSecureCoding: true)
        let tiffMagics: [[UInt8]] = [[0x49, 0x49, 0x2A, 0x00], [0x4D, 0x4D, 0x00, 0x2A]]
        var corrupted = false
        data.withUnsafeMutableBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            guard bytes.count > 4 else { return }
            for i in 0..<(bytes.count - 4) where !corrupted {
                for magic in tiffMagics where bytes[i] == magic[0] && bytes[i + 1] == magic[1]
                    && bytes[i + 2] == magic[2] && bytes[i + 3] == magic[3] {
                    bytes[i] = 0xFF; bytes[i + 1] = 0xFF; bytes[i + 2] = 0xFF; bytes[i + 3] = 0xFF
                    corrupted = true
                }
            }
        }
        XCTAssertTrue(corrupted, "Test setup failed: TIFF magic not found in archived NSImage")
        return data
    }

    /// Mirrors the decode performed by `EncryptedValueTransformer<NSImage>` via the
    /// `NSKeyedUnarchiver+DecodingFailurePolicy` helper.
    private func decodeImage(from data: Data) throws -> NSImage? {
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
        unarchiver.decodingFailurePolicy = .setErrorAndReturn
        unarchiver.requiresSecureCoding = true
        let object = unarchiver.decodeObject(of: NSImage.self, forKey: NSKeyedArchiveRootObjectKey)
        unarchiver.finishDecoding()
        return object
    }

    /// Documents the precondition: corrupt bitmap data raises an ObjC exception that `.setErrorAndReturn`
    /// and Swift `try?` do NOT catch – so it can only be caught with `NSException.catch`.
    func testDecodingCorruptArchivedImageRaisesUncatchableObjCException() throws {
        let data = try makeCorruptArchivedImageData()
        var raisedObjCException = false
        do {
            _ = try NSException.catch { try? self.decodeImage(from: data) }
        } catch {
            raisedObjCException = true
        }
        XCTAssertTrue(raisedObjCException, "Expected decoding corrupt TIFF data to raise an ObjC NSException")
    }

    /// Verifies the fix: wrapping the decode in `NSException.catch` (as `FaviconStore` now does) turns the
    /// crash into a graceful `nil` image.
    func testFaviconImageDecodingCatchesCorruptDataAndReturnsNilWithoutCrashing() throws {
        let data = try makeCorruptArchivedImageData()
        let image = try? NSException.catch { try? self.decodeImage(from: data) }
        XCTAssertNil(image, "Corrupt favicon image should decode to nil instead of crashing")
    }

}
