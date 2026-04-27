//
//  SyncSettingsViewController+PDFRendering.swift
//  DuckDuckGo
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

import SwiftUI
import Combine
import SyncUI_iOS
import DDGSync
import Core

extension SyncSettingsViewController {

    // Base list of activity types that don't make sense for sharing a sync recovery code in any form (plain text or PDF).
    private var recoveryShareBaseExcludedActivityTypes: [UIActivity.ActivityType] {
        var types: [UIActivity.ActivityType] = [
            .postToFacebook,
            .postToTwitter,
            .postToWeibo,
            .postToTencentWeibo,
            .postToFlickr,
            .postToVimeo,
            .assignToContact,
            .saveToCameraRoll,
            .addToReadingList
        ]
        if #available(iOS 15.4, *) {
            types.append(.sharePlay)
        }
        if #available(iOS 16.0, *) {
            types.append(contentsOf: [.collaborationInviteWithLink, .collaborationCopyLink])
        }
        if #available(iOS 16.4, *) {
            types.append(.addToHomeScreen)
        }
        return types
    }

    // Text-code share: also exclude activities that only make sense for rich documents.
    private var recoveryCodeExcludedActivityTypes: [UIActivity.ActivityType] {
        recoveryShareBaseExcludedActivityTypes + [
            .openInIBooks,
            .markupAsPDF,
            .print
        ]
    }

    // PDF share: allow Books and Print.
    private var recoveryPDFExcludedActivityTypes: [UIActivity.ActivityType] {
        recoveryShareBaseExcludedActivityTypes
    }

    func shareRecoveryPDF() {

        authenticateUser { [weak self] error in
            guard error == nil, let self else { return }

            let data = RecoveryPDFGenerator()
                .generate(recoveryCode)

            let pdf = RecoveryCodeItem(data: data)

            navigationController?.visibleViewController?.presentShareSheet(withItems: [pdf],
                                                                           fromView: view,
                                                                           additionalExcludedActivityTypes: recoveryPDFExcludedActivityTypes)
        }
    }

    func shareCode(_ code: String) {

        navigationController?.visibleViewController?.presentShareSheet(withItems: [code],
                                                                       fromView: view,
                                                                       overrideInterfaceStyle: .dark,
                                                                       additionalExcludedActivityTypes: recoveryCodeExcludedActivityTypes) { activity, didComplete, _, _  in
            guard case .copyToPasteboard = activity, didComplete else {
                return
            }
            guard let code = try? SyncCode.decodeBase64String(code) else {
                return
            }
            if code.connect != nil {
                Pixel.fire(pixel: .syncSetupBarcodeCodeCopied, withAdditionalParameters: [PixelParameters.source: SyncSetupSource.connect.rawValue])
            } else if code.exchangeKey != nil {
                Pixel.fire(pixel: .syncSetupBarcodeCodeCopied, withAdditionalParameters: [PixelParameters.source: SyncSetupSource.exchange.rawValue])
            }
        }
    }

}

private class RecoveryCodeItem: NSObject, UIActivityItemSource {

    let data: Data

    init(data: Data) {
        self.data = data
        super.init()
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return URL(fileURLWithPath: "Sync Data Recovery - DuckDuckGo.pdf")
    }

    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        data
    }

}
