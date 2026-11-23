//
//  AIChatScreenshotProvider.swift
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
import PixelKit
import PrivacyConfig
import WebKit

/// Which surface hosted the Duck.ai page that asked for the screenshot. Raw values are the pixel `source` parameter.
enum AIChatScreenshotRequestSource: String {
    case sidebar
    case duckai
}

/// Params of Duck.ai's `captureScreenshot` request.
struct AIChatCaptureScreenshotRequest: Decodable {
    let mode: String
}

/// Reply to Duck.ai's `captureScreenshot`, the same shape as the NTP `omnibar_captureScreenshot` reply.
/// Neither field set means the user cancelled, and the page shows nothing.
struct AIChatCaptureScreenshotResponse: Encodable, Equatable {
    struct Image: Encodable, Equatable {
        /// Base64 without a data-URL prefix.
        let data: String
        let format: String
        let kind: String
    }

    let image: Image?
    let error: String?

    static let cancelled = AIChatCaptureScreenshotResponse(image: nil, error: nil)
    static let failed = AIChatCaptureScreenshotResponse(image: nil, error: "screenshotFailed")
}

/// Native capture behind Duck.ai's "Add Screenshot". The page keeps its own attachment code;
/// native only acquires the image.
@MainActor
protocol AIChatScreenshotProviding: AnyObject {
    /// `nil` omits `screenshotModes` from the config and hides the screenshot UI.
    var screenshotModes: [String]? { get }

    /// Replies once the capture is taken, fails or is cancelled, however long the user takes.
    func captureScreenshot(mode: String,
                           requestingWebView: WKWebView?,
                           source: AIChatScreenshotRequestSource) async -> AIChatCaptureScreenshotResponse
}

@MainActor
final class AIChatScreenshotProvider: AIChatScreenshotProviding {

    private let featureFlagger: FeatureFlagger
    private let injectedCaptureService: AIChatScreenshotCaptureService?
    private let pixelFiring: PixelFiring?

    /// Read only when a capture starts, so building the config never touches the app delegate.
    private var captureService: AIChatScreenshotCaptureService {
        injectedCaptureService ?? NSApp.delegateTyped.aiChatScreenshotCaptureService
    }

    init(featureFlagger: FeatureFlagger,
         captureService: AIChatScreenshotCaptureService? = nil,
         pixelFiring: PixelFiring? = PixelKit.shared) {
        self.featureFlagger = featureFlagger
        self.injectedCaptureService = captureService
        self.pixelFiring = pixelFiring
    }

    var screenshotModes: [String]? {
        guard featureFlagger.isFeatureOn(.aiChatDuckAiScreenshot) else { return nil }
        return [AIChatScreenshotMode.dragToSelect.rawValue, AIChatScreenshotMode.selectWindowOrDisplay.rawValue]
    }

    func captureScreenshot(mode: String,
                           requestingWebView webView: WKWebView?,
                           source: AIChatScreenshotRequestSource) async -> AIChatCaptureScreenshotResponse {
        guard screenshotModes != nil, let mode = AIChatScreenshotMode(rawValue: mode) else { return .cancelled }

        // Switching tabs hides the chat that asked (a sidebar or a Duck.ai tab), so it ends the capture.
        let window = webView?.window
        let tabs = (window?.windowController as? MainWindowController)?.mainViewController.tabCollectionViewModel
        let tabChanged = tabs?.$selectedTabViewModel
            .map { $0.map(ObjectIdentifier.init) }
            .removeDuplicates()
            .dropFirst()
            .map { _ in () }
            .eraseToAnyPublisher()
        let captureService = captureService
        let result = await captureService.capture(mode: mode,
                                                  excluding: [],
                                                  returningFocusTo: window,
                                                  cancellingOn: tabChanged ?? Empty().eraseToAnyPublisher())

        switch result {
        case .image(let screenshot):
            pixelFiring?.fire(AIChatPixel.aiChatDuckAiScreenshotTaken(kind: screenshot.kind, source: source), frequency: .dailyAndCount)
            return .init(image: .init(data: screenshot.data.base64EncodedString(),
                                      format: screenshot.format.rawValue,
                                      kind: screenshot.kind.rawValue),
                         error: nil)
        case .cancelled:
            return .cancelled
        case .permissionDenied:
            // The alert explains, so the capture itself is a cancel and the page shows no error.
            captureService.presentPermissionAlert(on: window)
            return .cancelled
        case .failed(let reason):
            pixelFiring?.fire(AIChatPixel.aiChatDuckAiScreenshotFailed(reason: reason, source: source), frequency: .dailyAndCount)
            return .failed
        }
    }
}
