//
//  PassKitPreviewHelper.swift
//  DuckDuckGo
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

import Common
import Core
import UIKit
import PassKit
import os.log

class PassKitPreviewHelper: FilePreview {
    private weak var viewController: UIViewController?
    private let filePath: URL
    private let pixelFiring: PixelFiring.Type

    required convenience init(_ filePath: URL, viewController: UIViewController) {
        self.init(filePath, viewController: viewController, pixelFiring: Pixel.self)
    }

    init(_ filePath: URL, viewController: UIViewController, pixelFiring: PixelFiring.Type) {
        self.filePath = filePath
        self.viewController = viewController
        self.pixelFiring = pixelFiring
    }

    func preview() {
        do {
            let data = try Data(contentsOf: self.filePath)
            let pass = try PKPass(data: data)
            if let controller = PKAddPassesViewController(pass: pass) {
                viewController?.present(controller, animated: true)
            }
        } catch {
            Logger.general.error("Can't present passkit: \(error.localizedDescription, privacy: .public)")
            pixelFiring.fire(.walletPassPreviewFailed,
                             withAdditionalParameters: [PassKitPreviewHelper.reasonParameterKey: Self.failureReason(for: error)])
        }
    }

    static let reasonParameterKey = "reason"

    /// Categorises the localized error string returned by `PKPass` or `Data(contentsOf:)` into one of the
    /// `wallet_pass_preview_failed` reason enum values. Best-effort matching on observed PassKit messages.
    /// Locale-dependent: PassKit localises its error strings, so non-English devices fall through to
    /// `parse_error`. The matchers avoid apostrophes, which PassKit emits as the curly U+2019 form.
    static func failureReason(for error: Error) -> String {
        let message = error.localizedDescription.lowercased()
        if message.contains("no data") {
            return "no_data_supplied"
        }
        if message.contains("signature") || message.contains("cannot be read") {
            return "signature_invalid"
        }
        return "parse_error"
    }
}
