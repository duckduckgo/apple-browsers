//
//  MockNewTabPageOmnibarScreenshotProvider.swift
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

import Combine
import WebKit
@testable import NewTabPage

@MainActor
final class MockNewTabPageOmnibarScreenshotProvider: NewTabPageOmnibarScreenshotProviding {

    @Published var screenshotModes: [String]?
    @Published var enablePastedAttachments = false
    var captureResponse = NewTabPageDataModel.OmnibarCaptureScreenshotResponse.cancelled
    private(set) var requestedModes: [String] = []

    var configChangesPublisher: AnyPublisher<Void, Never> {
        $screenshotModes.dropFirst().map { _ in () }
            .merge(with: $enablePastedAttachments.dropFirst().map { _ in () })
            .eraseToAnyPublisher()
    }

    func captureScreenshot(mode: String, requestingWebView: WKWebView?) async -> NewTabPageDataModel.OmnibarCaptureScreenshotResponse {
        requestedModes.append(mode)
        return captureResponse
    }
}
