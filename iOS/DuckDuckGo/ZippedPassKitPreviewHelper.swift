//
//  ZippedPassKitPreviewHelper.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import Foundation
import UIKit
import PassKit
import ZIPFoundation
import os.log

class ZippedPassKitPreviewHelper: FilePreview {
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
        let entries: [Data]
        do {
            entries = try extractDataEntriesFromZipAtFilePath(self.filePath)
        } catch {
            // ZIP-side failures (missing file, corrupt archive) mean no pass bytes reached PassKit, mirroring
            // the file-read failure path in PassKitPreviewHelper.preview().
            Logger.general.error("Can't present passkit: \(error.localizedDescription, privacy: .public)")
            pixelFiring.fire(.walletPassPreviewFailed,
                             withAdditionalParameters: [PassKitPreviewHelper.reasonParameterKey: "no_data_supplied"])
            return
        }

        guard !entries.isEmpty else {
            Logger.general.error("Can't present passkit: empty passes archive")
            pixelFiring.fire(.walletPassPreviewFailed,
                             withAdditionalParameters: [PassKitPreviewHelper.reasonParameterKey: "no_data_supplied"])
            return
        }

        let passes: [PKPass] = entries.compactMap({ try? PKPass(data: $0) })
        guard !passes.isEmpty, let controller = PKAddPassesViewController(passes: passes) else {
            Logger.general.error("Can't present passkit: No valid passes in passes file")
            pixelFiring.fire(.walletPassPreviewFailed,
                             withAdditionalParameters: [PassKitPreviewHelper.reasonParameterKey: "parse_error"])
            return
        }

        viewController?.present(controller, animated: true)
    }

    func extractDataEntriesFromZipAtFilePath(_ zipPath: URL) throws -> [Data] {
        var dataObjects = [Data]()
        let archive = try Archive(url: zipPath, accessMode: .read)
        try archive.forEach { entry in
            var passData = Data()
            _ = try archive.extract(entry, skipCRC32: true) { data in
                passData.append(data)
            }

            if passData.count > 0 {
                dataObjects.append(passData)
            }
        }

        return dataObjects
    }
}
