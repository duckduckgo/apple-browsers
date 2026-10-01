//
//  AttachmentPrivacyDisclosurePixel.swift
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

import os.log
import PixelKit

/// Which native surface reported the disclosure. Shares the usage-warning card's raw values where
/// the surfaces match, so the series can be read side by side.
enum AttachmentPrivacyDisclosurePixelSurface: String {
    case addressBar = "address_bar"
    case promptBar = "prompt_bar"
    case newTabPage = "new_tab_page"
}

/// The file-upload privacy disclosure's pixels. What was attached is in the name rather than in a
/// parameter, so image and file are separate series; the surface is a parameter.
///
/// Duck.ai's own display is not reported here: the web app asks native for the display and fires
/// its own pixel, so reporting it again would double count.
enum AttachmentPrivacyDisclosurePixel: PixelKit.Event {

    case imageShown(AttachmentPrivacyDisclosurePixelSurface)
    case fileShown(AttachmentPrivacyDisclosurePixelSurface)
    case learnMoreTapped(AttachmentPrivacyDisclosurePixelSurface)

    private enum Parameter {
        static let surface = "surface"
    }

    static func shown(kind: AttachmentPrivacyDisclosureKind,
                      surface: AttachmentPrivacyDisclosurePixelSurface) -> AttachmentPrivacyDisclosurePixel {
        switch kind {
        case .image: return .imageShown(surface)
        case .file: return .fileShown(surface)
        }
    }

    var name: String {
        switch self {
        case .imageShown: return "aichat_attachment_privacy_image_shown"
        case .fileShown: return "aichat_attachment_privacy_file_shown"
        case .learnMoreTapped: return "aichat_attachment_privacy_learn_more_tapped"
        }
    }

    var parameters: [String: String]? {
        [Parameter.surface: surface.rawValue]
    }

    var standardParameters: [PixelKitStandardParameter]? { nil }

    private var surface: AttachmentPrivacyDisclosurePixelSurface {
        switch self {
        case .imageShown(let surface), .fileShown(let surface), .learnMoreTapped(let surface):
            return surface
        }
    }
}

struct AttachmentPrivacyDisclosurePixelFirer {

    private let surface: AttachmentPrivacyDisclosurePixelSurface
    private let pixelFiring: PixelFiring?

    init(surface: AttachmentPrivacyDisclosurePixelSurface, pixelFiring: PixelFiring? = PixelKit.shared) {
        self.surface = surface
        self.pixelFiring = pixelFiring
    }

    func fireShown(kind: AttachmentPrivacyDisclosureKind) {
        fire(.shown(kind: kind, surface: surface))
    }

    func fireLearnMoreTapped() {
        fire(.learnMoreTapped(surface))
    }

    private func fire(_ pixel: AttachmentPrivacyDisclosurePixel) {
        Logger.aiChat.debug("Attachment privacy pixel: \(pixel.name, privacy: .public)")
        // `Options.default` carries the app version, which is what these definitions declare.
        pixelFiring?.fire(pixel, frequency: .dailyAndCount)
    }
}
