//
//  NavigationResponseRouter.swift
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

import BrowserServicesKit
import Core
import Foundation
import PrivacyConfig

/// Decides which routing branch should fire for a given navigation response.
///
/// The decision logic is pulled out of `TabViewController.handleNavigationResponse` so the
/// per-branch outcome and its accompanying pixel firing can be exercised in isolation.
/// Side effects beyond decision-time pixels (starting downloads, presenting prompts,
/// touching view state, building download metadata) stay in the caller.
struct NavigationResponseRouter {

    /// The subset of `WKNavigationResponse` plus tab-side state that the routing logic reads.
    struct ResponseShape {
        let url: URL?
        let mimeType: MIMEType
        let canShowMIMEType: Bool
        let suggestedFilename: String?
        let isContentDispositionAttachment: Bool
        let didNavigationActionRequestDownload: Bool
        let urlSchemeType: SchemeHandler.SchemeType
        let urlNavigationalScheme: URL.NavigationalScheme?
        let hasTemporaryBlobDownload: Bool
    }

    /// Which branch of the policy decision the caller should run.
    enum Decision: Equatable {
        /// BLOB whose temporary download was already produced; let the web view load it.
        case blobAllow
        /// BLOB seen for the first time; trigger the download flow.
        case blobDownload
        /// Auto-previewable type that must persist to Downloads (ICS today), or for which the
        /// `walletPassDownload` failsafe is off. Caller runs the legacy `URLSession` path.
        case autoPreviewPersist
        /// Auto-previewable type routed through the modern `WKDownload`-continuation path.
        /// Caller returns `.download` and lets the `didBecome download:` handler finish the job.
        case autoPreviewTransient
        /// `data:` URL the caller should hand off to WebKit's native download.
        case dataSchemeDownload
        /// Caller should attempt to build download metadata and present the save prompt.
        /// If metadata cannot be built, the caller falls back to `webViewPreview` or `allowDefault`
        /// to preserve current behavior.
        case userPromptDownload
        /// WebView can render the MIME inline (HTML and similar).
        case webViewPreview
        /// Defensive fallback. Unreachable in current logic because `shouldTriggerDownload` returns true
        /// whenever `canLoadOrPreview` is false, but kept so a future change cannot accidentally drop a path.
        case allowDefault
    }

    private let featureFlagger: FeatureFlagger
    private let pixelFiring: PixelFiring.Type

    init(featureFlagger: FeatureFlagger, pixelFiring: PixelFiring.Type = Pixel.self) {
        self.featureFlagger = featureFlagger
        self.pixelFiring = pixelFiring
    }

    func decide(for shape: ResponseShape) -> Decision {
        if shape.urlSchemeType == .blob {
            return shape.hasTemporaryBlobDownload ? .blobAllow : .blobDownload
        }

        if FilePreviewHelper.canAutoPreviewMIMEType(shape.mimeType) ||
            FilePreviewHelper.canAutoPreviewICSByExtension(url: shape.url,
                                                           filename: shape.suggestedFilename,
                                                           featureFlagger: featureFlagger) {
            pixelFiring.fire(.downloadStarted,
                             withAdditionalParameters: [PixelParameters.canAutoPreviewMIMEType: "1"])

            if shape.mimeType == .passbook || shape.mimeType == .multipass {
                pixelFiring.fire(.walletPassPreviewRequested,
                                 withAdditionalParameters: [:])
            }

            let shouldPersist = FilePreviewHelper.shouldPersistInDownloads(mimeType: shape.mimeType,
                                                                           url: shape.url,
                                                                           filename: shape.suggestedFilename,
                                                                           featureFlagger: featureFlagger)
            if shouldPersist || !featureFlagger.isFeatureOn(.walletPassDownload) {
                return .autoPreviewPersist
            }
            return .autoPreviewTransient
        }

        if shouldTriggerDownload(for: shape) {
            if shape.urlNavigationalScheme == .data {
                return .dataSchemeDownload
            }
            return .userPromptDownload
        }

        if shape.canShowMIMEType {
            return .webViewPreview
        }

        return .allowDefault
    }

    private func shouldTriggerDownload(for shape: ResponseShape) -> Bool {
        let canLoadOrPreview = shape.canShowMIMEType || FilePreviewHelper.canAutoPreviewMIMEType(shape.mimeType)
        return shape.isContentDispositionAttachment || shape.didNavigationActionRequestDownload || !canLoadOrPreview
    }
}
