//
//  UserText.swift
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

#if os(iOS)
import Foundation
import FoundationExtensions

public struct UserText {
    public static let downloadComplete = NSLocalizedString("aichat.download.complete", bundle: .aiChatLocalizations, value: "Download complete for %@", comment: "Download complete for duck.ai")
    public static let downloadToastShow = NSLocalizedString("aichat.download.show", bundle: .aiChatLocalizations, value: "Show", comment: "Show button for downloads")
    public static let downloadFailed = NSLocalizedString("aichat.download.failed", bundle: .aiChatLocalizations, value: "Download failed", comment: "Download failed message")
    public static let modelPickerLabelEverydayUse = NSLocalizedString(
        "aichat.model-picker.label.everyday-use",
        bundle: .aiChatLocalizations,
        value: "Best for everyday use",
        comment: "Editorial descriptor shown beneath a model in the model picker when it is recommended for everyday use"
    )
    public static let modelPickerLabelUsesLimitsFaster = NSLocalizedString(
        "aichat.model-picker.label.uses-limits-faster",
        bundle: .aiChatLocalizations,
        value: "Solid but hits limits sooner",
        comment: "Editorial descriptor shown beneath a model in the model picker when it consumes usage limits faster"
    )
    public static let attachPageContent = NSLocalizedString("duckai.contextual.attach.content", bundle: .aiChatLocalizations, value: "Attach Page Content", comment: "Title for the attach placeholder chip in Duck.ai contextual sheet")
    public static let askAboutPage = NSLocalizedString("duckai.contextual.ask.about.page", bundle: .aiChatLocalizations, value: "Ask About Page", comment: "Title for the button that re-attaches the current page's content after the user removed it")

}

private final class BundleMarker {}

private extension Bundle {

    /// `Bundle.module` traps when the package's resource bundle is not next to the binary, which is
    /// how these tests run from the iOS app scheme. Falls back to the module's own bundle instead,
    /// leaving `NSLocalizedString` to use its default value.
    static let aiChatLocalizations: Bundle = {
        let marker = Bundle(for: BundleMarker.self)
        let candidates = [marker.resourceURL, Bundle.main.resourceURL, marker.bundleURL, Bundle.main.bundleURL]
        for url in candidates.compactMap({ $0?.appendingPathComponent("AIChat_AIChat.bundle") }) {
            if let bundle = Bundle(url: url) { return bundle }
        }
        return marker
    }()
}
#endif
