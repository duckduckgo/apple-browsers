//
//  MockScanOrPasteCodeViewModelDelegate.swift
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
@testable import SyncUI_iOS

final class MockScanOrPasteCodeViewModelDelegate: ScanOrPasteCodeViewModelDelegate {

    var pasteboardString: String?
    var syncCodeEnteredResult = false

    private(set) var didCallEndConnectMode = false
    private(set) var syncCodeEnteredCalls: [(code: String, source: CodeEntrySource)] = []
    private(set) var codeCollectionCancelledSources: [CodeCollectionSource] = []
    private(set) var didCallGotoSettings = false
    private(set) var requestCameraPermissionModels: [ScanOrPasteCodeViewModel] = []
    private(set) var shareCodeCalls: [(code: String, source: CodeCollectionSource)] = []
    private(set) var didCallCodeEntryScreenShown = false
    private(set) var codeCopiedCalls: [(code: String, source: CodeCollectionSource)] = []

    func endConnectMode() {
        didCallEndConnectMode = true
    }

    func syncCodeEntered(code: String, source: CodeEntrySource) async -> Bool {
        syncCodeEnteredCalls.append((code, source))
        return syncCodeEnteredResult
    }

    func codeCollectionCancelled(source: CodeCollectionSource) {
        codeCollectionCancelledSources.append(source)
    }

    func gotoSettings() {
        didCallGotoSettings = true
    }

    func requestCameraPermission(for model: ScanOrPasteCodeViewModel) {
        requestCameraPermissionModels.append(model)
    }

    func shareCode(_ code: String, source: CodeCollectionSource) {
        shareCodeCalls.append((code, source))
    }

    func codeEntryScreenShown() {
        didCallCodeEntryScreenShown = true
    }

    func codeCopied(_ code: String, source: CodeCollectionSource) {
        codeCopiedCalls.append((code, source))
    }
}
