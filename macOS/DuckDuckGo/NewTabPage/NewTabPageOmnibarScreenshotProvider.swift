//
//  NewTabPageOmnibarScreenshotProvider.swift
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

import AppKit
import Combine
import FeatureFlags_macOS
import NewTabPage
import PixelKit
import PrivacyConfig
import WebKit

@MainActor
final class NewTabPageOmnibarScreenshotProvider: NewTabPageOmnibarScreenshotProviding {

    private let featureFlagger: FeatureFlagger
    private let captureService: AIChatScreenshotCaptureService
    private let firePixel: (AIChatPixel) -> Void

    /// `captureService` is resolved in the body: a default argument is evaluated off the main actor.
    init(featureFlagger: FeatureFlagger,
         captureService: AIChatScreenshotCaptureService? = nil,
         firePixel: @escaping (AIChatPixel) -> Void = { PixelKit.fire($0, frequency: .dailyAndCount, includeAppVersionParameter: true) }) {
        self.featureFlagger = featureFlagger
        self.captureService = captureService ?? .shared
        self.firePixel = firePixel
    }

    var screenshotModes: [String]? {
        guard featureFlagger.isFeatureOn(.aiChatNtpScreenshot) else { return nil }
        return [AIChatScreenshotMode.dragToSelect.rawValue, AIChatScreenshotMode.selectWindowOrDisplay.rawValue]
    }

    var enablePastedAttachments: Bool {
        featureFlagger.isFeatureOn(.aiChatNtpPasteImages)
    }

    /// `map`, not `compactMap` like the neighbouring flag publishers: `nil` (flag off) must reach the
    /// page so an open New Tab Page hides Add Screenshot.
    var configChangesPublisher: AnyPublisher<Void, Never> {
        let current = (screenshotModes, enablePastedAttachments)
        return featureFlagger.updatesPublisher
            .map { [weak self] in (self?.screenshotModes, self?.enablePastedAttachments ?? false) }
            .prepend(current)
            .removeDuplicates { $0 == $1 }
            .dropFirst()
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    func captureScreenshot(mode: String, requestingWebView webView: WKWebView?) async -> NewTabPageDataModel.OmnibarCaptureScreenshotResponse {
        guard screenshotModes != nil, let mode = AIChatScreenshotMode(rawValue: mode) else { return .cancelled }

        // A window's New Tab Pages share one web view, so the selected tab tells when the asking one is gone.
        let window = webView?.window
        let tabs = (window?.windowController as? MainWindowController)?.mainViewController.tabCollectionViewModel
        let tabChanged = tabs?.$selectedTabViewModel
            .map { $0.map(ObjectIdentifier.init) }
            .removeDuplicates()
            .dropFirst()
            .map { _ in () }
            .eraseToAnyPublisher()
        let result = await captureService.capture(mode: mode,
                                                  excluding: [],
                                                  returningFocusTo: window,
                                                  cancellingOn: tabChanged ?? Empty().eraseToAnyPublisher())
        // The page reports taken and its own processing failures; native reports what fails before the page sees an image.
        if let reason = result.failureReason {
            firePixel(.aiChatNtpScreenshotFailed(reason: reason))
        }

        switch result {
        case .image(let screenshot):
            return .init(image: .init(data: screenshot.data.base64EncodedString(),
                                      format: screenshot.format.rawValue,
                                      kind: screenshot.kind.rawValue))
        case .cancelled:
            return .cancelled
        case .permissionDenied:
            // The alert explains, so the capture itself is a cancel and the page shows no error.
            captureService.presentPermissionAlert(on: webView?.window)
            return .cancelled
        case .failed:
            return .failed
        }
    }
}
