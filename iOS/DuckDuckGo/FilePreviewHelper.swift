//
//  FilePreviewHelper.swift
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

import BrowserServicesKit
import Core
import PrivacyConfig
import UIKit

struct FilePreviewHelper {

    static func fileHandlerForDownload(_ download: Download, viewController: UIViewController, featureFlagger: FeatureFlagger) -> FilePreview? {
        guard let filePath = download.location else { return nil }
        switch download.mimeType {
        case .passbook:
            return PassKitPreviewHelper(filePath, viewController: viewController)
        case .multipass:
            return ZippedPassKitPreviewHelper(filePath, viewController: viewController)
        case .calendar where featureFlagger.isFeatureOn(.icsCalendarLinks):
            return CalendarEventPreviewHelper(filePath, viewController: viewController)
        default:
            if featureFlagger.isFeatureOn(.icsCalendarLinks), filePath.pathExtension.lowercased() == "ics" {
                Pixel.fire(pixel: .icsCalendarRoutedByExtension)
                return CalendarEventPreviewHelper(filePath, viewController: viewController)
            }
            return QuickLookPreviewHelper(filePath, viewController: viewController)
        }
    }
    
    static func canAutoPreviewMIMEType(_ mimeType: MIMEType) -> Bool {
        switch mimeType {
        case .passbook, .multipass:
            return UIDevice.current.userInterfaceIdiom == .phone

        case .reality, .usdz, .calendar:
            return true
        default:
            return false
        }
    }

    /// Auto-preview .ics by URL or filename extension when the MIME type is wrong.
    static func canAutoPreviewICSByExtension(url: URL?,
                                             filename: String?,
                                             featureFlagger: FeatureFlagger) -> Bool {
        guard featureFlagger.isFeatureOn(.icsCalendarLinks) else { return false }
        if url?.pathExtension.lowercased() == "ics" { return true }
        if filename?.lowercased().hasSuffix(".ics") == true { return true }
        return false
    }

    /// ICS files must persist so the user can retry from Downloads when auto-add fails.
    static func shouldPersistInDownloads(mimeType: MIMEType,
                                         url: URL?,
                                         filename: String?,
                                         featureFlagger: FeatureFlagger) -> Bool {
        guard featureFlagger.isFeatureOn(.icsCalendarLinks) else { return false }
        return isICS(mimeType: mimeType, url: url, filename: filename)
    }

    /// File types handed off to a native handler; download started/finished toasts are suppressed for these.
    static func handlesDownloadNatively(mimeType: MIMEType,
                                        url: URL?,
                                        filename: String?,
                                        featureFlagger: FeatureFlagger) -> Bool {
        guard featureFlagger.isFeatureOn(.icsCalendarLinks) else { return false }
        return isICS(mimeType: mimeType, url: url, filename: filename)
    }

    private static func isICS(mimeType: MIMEType, url: URL?, filename: String?) -> Bool {
        if mimeType == .calendar { return true }
        if url?.pathExtension.lowercased() == "ics" { return true }
        if filename?.lowercased().hasSuffix(".ics") == true { return true }
        return false
    }
}
