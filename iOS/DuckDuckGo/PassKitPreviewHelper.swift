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
import FoundationExtensions
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
        let data: Data
        do {
            data = try Data(contentsOf: self.filePath)
        } catch {
            Logger.general.error("Can't present passkit: \(error.localizedDescription, privacy: .public)")
            pixelFiring.fire(.walletPassPreviewFailed,
                             withAdditionalParameters: [Self.reasonParameterKey: "no_data_supplied"])
            return
        }

        guard !data.isEmpty else {
            Logger.general.error("Can't present passkit: empty pass data")
            pixelFiring.fire(.walletPassPreviewFailed,
                             withAdditionalParameters: [Self.reasonParameterKey: "no_data_supplied"])
            return
        }

        do {
            let pass = try PKPass(data: data)
            if let controller = PKAddPassesViewController(pass: pass) {
                viewController?.present(controller, animated: true)
            }
        } catch {
            Logger.general.error("Can't present passkit: \(error.localizedDescription, privacy: .public)")
            pixelFiring.fire(.walletPassPreviewFailed,
                             withAdditionalParameters: [Self.reasonParameterKey: Self.failureReason(for: error)])
        }
    }

    static let reasonParameterKey = "reason"

    /// Maps a `PKPass(data:)` error to one of the `wallet_pass_preview_failed` reasons using the
    /// `PKPassKitErrorDomain` NSError code so the categorisation works in all locales.
    /// Callers handle `no_data_supplied` (empty / unreadable input) before reaching this function.
    static func failureReason(for error: Error) -> String {
        let nsError = error as NSError
        guard nsError.domain == PKPassKitErrorDomain else {
            return "parse_error"
        }
        switch PKPassKitError.Code(rawValue: nsError.code) {
        case .invalidSignature:
            return "signature_invalid"
        default:
            return "parse_error"
        }
    }
}
