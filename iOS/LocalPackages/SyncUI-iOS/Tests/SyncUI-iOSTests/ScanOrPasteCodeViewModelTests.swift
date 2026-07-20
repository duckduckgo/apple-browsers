//
//  ScanOrPasteCodeViewModelTests.swift
//  DuckDuckGo
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
import Testing
@testable import SyncUI_iOS

@MainActor
@Suite("Sync - Scan Or Paste Code View Model")
final class ScanOrPasteCodeViewModelTests {

    private let delegate = MockScanOrPasteCodeViewModelDelegate()

    private func makeSUT(source: CodeCollectionSource = .connect) -> ScanOrPasteCodeViewModel {
        let sut = ScanOrPasteCodeViewModel(codeForDisplayOrPasting: "code", qrCodeString: "qr", source: source)
        sut.delegate = delegate
        return sut
    }

    @available(iOS 16, macOS 13, *)
    @Test("Intro animation completed requests camera permission for the view model", .timeLimit(.minutes(1)))
    func introAnimationCompletedRequestsCameraPermission() {
        // GIVEN
        let sut = makeSUT()

        // WHEN
        sut.introAnimationCompleted()

        // THEN
        #expect(delegate.requestCameraPermissionModels.count == 1)
        #expect(delegate.requestCameraPermissionModels.first === sut)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Camera unavailable hides the camera", .timeLimit(.minutes(1)))
    func cameraUnavailableHidesCamera() {
        // GIVEN
        let sut = makeSUT()
        #expect(sut.showCamera == true)

        // WHEN
        sut.cameraUnavailable()

        // THEN
        #expect(sut.showCamera == false)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Cancel forwards the collection source", .timeLimit(.minutes(1)))
    func cancelForwardsSource() {
        // GIVEN
        let sut = makeSUT(source: .exchange)

        // WHEN
        sut.cancel()

        // THEN
        #expect(delegate.codeCollectionCancelledSources == [.exchange])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Goto settings is forwarded to the delegate", .timeLimit(.minutes(1)))
    func gotoSettingsIsForwarded() {
        // GIVEN
        let sut = makeSUT()

        // WHEN
        sut.gotoSettings()

        // THEN
        #expect(delegate.didCallGotoSettings)
    }

    @available(iOS 16, macOS 13, *)
    @Test("End connect mode is forwarded to the delegate", .timeLimit(.minutes(1)))
    func endConnectModeIsForwarded() {
        // GIVEN
        let sut = makeSUT()

        // WHEN
        sut.endConnectMode()

        // THEN
        #expect(delegate.didCallEndConnectMode)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Show share code sheet forwards the code and source", .timeLimit(.minutes(1)))
    func showShareCodeSheetForwardsCodeAndSource() {
        // GIVEN
        let sut = makeSUT(source: .recovery)

        // WHEN
        sut.showShareCodeSheet()

        // THEN
        #expect(delegate.shareCodeCalls.count == 1)
        #expect(delegate.shareCodeCalls.first?.code == "code")
        #expect(delegate.shareCodeCalls.first?.source == .recovery)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Copy code forwards the code and source when non-empty", .timeLimit(.minutes(1)))
    func copyCodeForwardsCodeWhenNonEmpty() {
        // GIVEN
        let sut = makeSUT(source: .connect)

        // WHEN
        sut.copyCode()

        // THEN
        #expect(delegate.codeCopiedCalls.count == 1)
        #expect(delegate.codeCopiedCalls.first?.code == "code")
        #expect(delegate.codeCopiedCalls.first?.source == .connect)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Copy code does nothing when the code is empty", .timeLimit(.minutes(1)))
    func copyCodeDoesNothingWhenEmpty() {
        // GIVEN
        let sut = ScanOrPasteCodeViewModel(codeForDisplayOrPasting: "", qrCodeString: "qr", source: .connect)
        sut.delegate = delegate

        // WHEN
        sut.copyCode()

        // THEN
        #expect(delegate.codeCopiedCalls.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Can submit manual code only when the trimmed code is non-empty", .timeLimit(.minutes(1)))
    func canSubmitManualCodeReflectsTrimmedContent() {
        // GIVEN
        let sut = makeSUT()

        // THEN
        #expect(sut.canSubmitManualCode == false)

        // WHEN
        sut.manuallyEnteredCode = "   \n "
        // THEN
        #expect(sut.canSubmitManualCode == false)

        // WHEN
        sut.manuallyEnteredCode = "abc"
        // THEN
        #expect(sut.canSubmitManualCode == true)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Paste code cleans whitespace and newlines from the pasteboard string", .timeLimit(.minutes(1)))
    func pasteCodeCleansPasteboardString() {
        // GIVEN
        let sut = makeSUT()
        delegate.pasteboardString = "  ab cd\nef  "

        // WHEN
        sut.pasteCode()

        // THEN
        #expect(sut.manuallyEnteredCode == "abcdef")
        #expect(sut.isValidating == true)
        #expect(sut.invalidCode == false)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Code scanned returns true when the delegate accepts the code", .timeLimit(.minutes(1)))
    func codeScannedReturnsDelegateResultWhenAccepted() async {
        // GIVEN
        let sut = makeSUT()
        delegate.syncCodeEnteredResult = true

        // WHEN
        let result = await sut.codeScanned("scanned-code")

        // THEN
        #expect(result == true)
        #expect(delegate.syncCodeEnteredCalls.count == 1)
        #expect(delegate.syncCodeEnteredCalls.first?.code == "scanned-code")
        #expect(delegate.syncCodeEnteredCalls.first?.source == .qrCode)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Code scanned returns false when the delegate rejects the code", .timeLimit(.minutes(1)))
    func codeScannedReturnsDelegateResultWhenRejected() async {
        // GIVEN
        let sut = makeSUT()
        delegate.syncCodeEnteredResult = false

        // WHEN
        let result = await sut.codeScanned("scanned-code")

        // THEN
        #expect(result == false)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Code for display strips the pairing URL and keeps the code2 payload", .timeLimit(.minutes(1)))
    func codeForDisplayStripsPairingURL() {
        // GIVEN
        let payload = "eyJ2ZXJzaW9uIjoiMiJ9"
        let url = "https://duckduckgo.com/sync/pairing/#&code2=\(payload)"
        let sut = ScanOrPasteCodeViewModel(codeForDisplayOrPasting: url, qrCodeString: url, source: .connect)

        // THEN
        #expect(sut.showQRCodeModel.codeForDisplay == payload)
        #expect(sut.showQRCodeModel.codeForDisplayOrPasting == url)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Code for display strips the pairing URL and keeps the legacy code payload", .timeLimit(.minutes(1)))
    func codeForDisplayStripsLegacyPairingURL() {
        // GIVEN
        let payload = "ABCDEFGHIJ"
        let url = "https://duckduckgo.com/sync/pairing/#&code=\(payload)&deviceName=iPhone"
        let sut = ScanOrPasteCodeViewModel(codeForDisplayOrPasting: url, qrCodeString: url, source: .connect)

        // THEN
        #expect(sut.showQRCodeModel.codeForDisplay == payload)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Code for display returns the code unchanged when it is not a pairing URL", .timeLimit(.minutes(1)))
    func codeForDisplayReturnsNonURLCodeUnchanged() {
        // GIVEN
        let code = "eyJyZWNvdmVyeSI6eyJ1c2VyX2lkIjoiMSJ9fQ=="
        let sut = ScanOrPasteCodeViewModel(codeForDisplayOrPasting: code, qrCodeString: code, source: .recovery)

        // THEN
        #expect(sut.showQRCodeModel.codeForDisplay == code)
    }
}
