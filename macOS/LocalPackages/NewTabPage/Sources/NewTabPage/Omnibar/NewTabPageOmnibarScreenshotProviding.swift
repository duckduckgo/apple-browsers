//
//  NewTabPageOmnibarScreenshotProviding.swift
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

/// Native capture behind the omnibar's Add Screenshot. The page keeps its own attachment code;
/// native only acquires the image.
@MainActor
public protocol NewTabPageOmnibarScreenshotProviding: AnyObject {

    /// `nil` omits the field and hides the screenshot UI (flag off).
    var screenshotModes: [String]? { get }

    /// Lets the page attach pasted images and copied files.
    var enablePastedAttachments: Bool { get }

    /// Fires when the modes or `enablePastedAttachments` change, so an open New Tab Page updates without a reload.
    var configChangesPublisher: AnyPublisher<Void, Never> { get }

    /// Replies once the capture is taken, fails or is cancelled, however long the user takes.
    func captureScreenshot(mode: String, requestingWebView: WKWebView?) async -> NewTabPageDataModel.OmnibarCaptureScreenshotResponse
}
