//
//  ScanOrPasteCodeViewModel.swift
//  DuckDuckGo
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
import UIKit

public enum CodeEntrySource: String {
    case qrCode
    case pastedCode
}

public enum CodeCollectionSource: String {
    case connect
    case exchange
    case recovery
}

public protocol ScanOrPasteCodeViewModelDelegate: AnyObject {

    var pasteboardString: String? { get }

    func endConnectMode()

    /// Returns true if we were able to use the code. Either way, stop validating.
    func syncCodeEntered(code: String, source: CodeEntrySource) async -> Bool

    func codeCollectionCancelled(source: CodeCollectionSource)
    func gotoSettings()
    func shareCode(_ code: String, source: CodeCollectionSource)

    func codeEntryScreenShown()
    func codeCopied(_ code: String, source: CodeCollectionSource)
}

public class ScanOrPasteCodeViewModel: ObservableObject {

    public enum VideoPermission {
        case unknown, authorised, denied
    }

    public enum State {
        case showScanner, manualEntry, showQRCode
    }

    public enum StartConnectModeResult {
        case authorised(code: String), denied, failed
    }

    @Published public var videoPermission: VideoPermission = .unknown

    @Published var showCamera = true
    @Published var state = State.showScanner
    @Published var manuallyEnteredCode: String?
    @Published var isValidating = false
    @Published var invalidCode = false

    var canSubmitManualCode: Bool {
        manuallyEnteredCode?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    public weak var delegate: ScanOrPasteCodeViewModelDelegate?

    var showQRCodeModel: ShowQRCodeViewModel
    private let source: CodeCollectionSource

    public init(codeForDisplayOrPasting: String, qrCodeString: String, source: CodeCollectionSource) {
        showQRCodeModel = ShowQRCodeViewModel(codeForDisplayOrPasting: codeForDisplayOrPasting, qrCodeString: qrCodeString)
        self.source = source
    }

    func codeScanned(_ code: String) async -> Bool {
        // Pre-emptively trigger haptic as soon as we detect a QR code.
        // This feels better than deferring until we've determined whether the code is valid.
        await MainActor.run {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        return await delegate?.syncCodeEntered(code: code, source: .qrCode) == true
    }

    func cameraUnavailable() {
        showCamera = false
    }

    @MainActor
    func copyCode() {
        guard showQRCodeModel.codeForDisplayOrPasting.isEmpty == false else { return }
        showQRCodeModel.copy()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        delegate?.codeCopied(showQRCodeModel.codeForDisplayOrPasting, source: source)
    }

    @MainActor
    func pasteCode() {
        guard let string = delegate?
            .pasteboardString?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "") else { return }

        self.manuallyEnteredCode = string
        invalidCode = false
        isValidating = true

        Task { @MainActor in
            let codeUsed = await delegate?.syncCodeEntered(code: string, source: .pastedCode) == true
            if !codeUsed {
                isValidating = false
                invalidCode = true
            }
        }
    }

    func cancel() {
        delegate?.codeCollectionCancelled(source: source)
    }

    func showShareCodeSheet() {
        delegate?.shareCode(showQRCodeModel.codeForDisplayOrPasting, source: source)
    }

    func endConnectMode() {
        self.delegate?.endConnectMode()
    }

    func gotoSettings() {
        delegate?.gotoSettings()
    }

}
