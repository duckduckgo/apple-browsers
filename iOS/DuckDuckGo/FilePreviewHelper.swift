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

    /// True when the URL points at an `.ics` file and we should auto-preview it as a calendar
    /// event despite the MIME type being something other than `text/calendar`. Gated on the
    /// ICS feature flag so behaviour on flag-off matches the pre-feature world.
    static func canAutoPreviewICSByExtension(_ url: URL?, featureFlagger: FeatureFlagger) -> Bool {
        guard featureFlagger.isFeatureOn(.icsCalendarLinks) else { return false }
        return url?.pathExtension.lowercased() == "ics"
    }
}
