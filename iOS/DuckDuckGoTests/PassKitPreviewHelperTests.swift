//
//  PassKitPreviewHelperTests.swift
//  DuckDuckGo
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

import Core
import Foundation
import PassKit
import Testing
import UIKit
@testable import DuckDuckGo

@Suite("PassKitPreviewHelper", .serialized)
final class PassKitPreviewHelperTests {

    init() {
        PixelFiringMock.tearDown()
    }

    deinit {
        PixelFiringMock.tearDown()
    }

    // MARK: - failureReason categorisation

    @available(iOS 16, *)
    @Test("Categorises PKInvalidSignature as signature_invalid", .timeLimit(.minutes(1)))
    func categorisesInvalidSignatureAsSignatureInvalid() {
        // GIVEN
        let error = NSError(domain: PKPassKitErrorDomain,
                            code: PKPassKitError.Code.invalidSignature.rawValue,
                            userInfo: nil)

        // WHEN
        let reason = PassKitPreviewHelper.failureReason(for: error)

        // THEN
        #expect(reason == "signature_invalid")
    }

    @available(iOS 16, *)
    @Test("Categorises PKInvalidDataError as parse_error", .timeLimit(.minutes(1)))
    func categorisesInvalidDataAsParseError() {
        // GIVEN
        // PassKit's PKInvalidDataError covers "data is present but not a valid pass". The empty-data
        // case is handled in preview() before PKPass is called, so this stays in the parse_error bucket.
        let error = NSError(domain: PKPassKitErrorDomain,
                            code: PKPassKitError.Code.invalidDataError.rawValue,
                            userInfo: nil)

        // WHEN
        let reason = PassKitPreviewHelper.failureReason(for: error)

        // THEN
        #expect(reason == "parse_error")
    }

    @available(iOS 16, *)
    @Test("Categorises PKUnsupportedVersionError as parse_error", .timeLimit(.minutes(1)))
    func categorisesUnsupportedVersionAsParseError() {
        // GIVEN
        let error = NSError(domain: PKPassKitErrorDomain,
                            code: PKPassKitError.Code.unsupportedVersionError.rawValue,
                            userInfo: nil)

        // WHEN
        let reason = PassKitPreviewHelper.failureReason(for: error)

        // THEN
        #expect(reason == "parse_error")
    }

    @available(iOS 16, *)
    @Test("Categorises a non-PassKit error as parse_error", .timeLimit(.minutes(1)))
    func categorisesNonPassKitErrorAsParseError() {
        // GIVEN
        let error = NSError(domain: "SomeOtherDomain", code: 0, userInfo: nil)

        // WHEN
        let reason = PassKitPreviewHelper.failureReason(for: error)

        // THEN
        #expect(reason == "parse_error")
    }

    // MARK: - preview() integration

    @available(iOS 16, *)
    @Test("Fires wallet_pass_preview_failed with no_data_supplied when the file does not exist", .timeLimit(.minutes(1)))
    @MainActor
    func firesNoDataSuppliedForMissingFile() {
        // GIVEN
        let nonExistent = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".pkpass")
        let helper = PassKitPreviewHelper(nonExistent,
                                          viewController: UIViewController(),
                                          pixelFiring: PixelFiringMock.self)

        // WHEN
        helper.preview()

        // THEN
        #expect(PixelFiringMock.lastPixelName == Pixel.Event.walletPassPreviewFailed.name)
        #expect(PixelFiringMock.lastParams?[PassKitPreviewHelper.reasonParameterKey] == "no_data_supplied")
    }

    @available(iOS 16, *)
    @Test("Fires wallet_pass_preview_failed with no_data_supplied when the file is empty", .timeLimit(.minutes(1)))
    @MainActor
    func firesNoDataSuppliedForEmptyFile() throws {
        // GIVEN
        let emptyFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".pkpass")
        try Data().write(to: emptyFile)
        defer { try? FileManager.default.removeItem(at: emptyFile) }

        let helper = PassKitPreviewHelper(emptyFile,
                                          viewController: UIViewController(),
                                          pixelFiring: PixelFiringMock.self)

        // WHEN
        helper.preview()

        // THEN
        #expect(PixelFiringMock.lastPixelName == Pixel.Event.walletPassPreviewFailed.name)
        #expect(PixelFiringMock.lastParams?[PassKitPreviewHelper.reasonParameterKey] == "no_data_supplied")
    }
}
