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
        case .contact where featureFlagger.isFeatureOn(.vcardContactLinks):
            return ContactPreviewHelper(filePath, viewController: viewController)
        default:
            if featureFlagger.isFeatureOn(.icsCalendarLinks), filePath.pathExtension.lowercased() == "ics" {
                Pixel.fire(pixel: .icsCalendarRoutedByExtension)
                return CalendarEventPreviewHelper(filePath, viewController: viewController)
            }
            if featureFlagger.isFeatureOn(.vcardContactLinks),
               hasVCardFileExtension(url: filePath, filename: nil) {
                Pixel.fire(pixel: .vcardContactRoutedByExtension)
                return ContactPreviewHelper(filePath, viewController: viewController)
            }
            return QuickLookPreviewHelper(filePath, viewController: viewController)
        }
    }
    
    static func canAutoPreviewMIMEType(_ mimeType: MIMEType) -> Bool {
        switch mimeType {
        case .passbook, .multipass:
            return UIDevice.current.userInterfaceIdiom == .phone

        case .reality, .usdz, .calendar, .contact:
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

    /// Auto-preview .vcf/.vcard by URL or filename extension when the MIME type is wrong.
    static func canAutoPreviewVCardByExtension(url: URL?,
                                               filename: String?,
                                               featureFlagger: FeatureFlagger) -> Bool {
        guard featureFlagger.isFeatureOn(.vcardContactLinks) else { return false }
        return hasVCardFileExtension(url: url, filename: filename)
    }

    /// Whether a download can be handed to a native auto-preview handler — by MIME type, or by a
    /// flagged .ics/.vcf extension when the MIME type is wrong. Single source of truth for the
    /// decision so callers (NavigationResponseRouter, TabViewController) stay in sync and a new
    /// previewable type is wired up in one place.
    static func canAutoPreview(mimeType: MIMEType,
                               url: URL?,
                               filename: String?,
                               featureFlagger: FeatureFlagger) -> Bool {
        canAutoPreviewMIMEType(mimeType)
            || canAutoPreviewICSByExtension(url: url, filename: filename, featureFlagger: featureFlagger)
            || canAutoPreviewVCardByExtension(url: url, filename: filename, featureFlagger: featureFlagger)
    }

    /// ICS and vCard files must persist so the user can retry from Downloads when auto-add fails.
    static func shouldPersistInDownloads(mimeType: MIMEType,
                                         url: URL?,
                                         filename: String?,
                                         featureFlagger: FeatureFlagger) -> Bool {
        if featureFlagger.isFeatureOn(.icsCalendarLinks), isICS(mimeType: mimeType, url: url, filename: filename) {
            return true
        }
        if featureFlagger.isFeatureOn(.vcardContactLinks), isVCard(mimeType: mimeType, url: url, filename: filename) {
            return true
        }
        return false
    }

    /// File types handed off to a native handler; download started/finished toasts are suppressed for these.
    static func handlesDownloadNatively(mimeType: MIMEType,
                                        url: URL?,
                                        filename: String?,
                                        featureFlagger: FeatureFlagger) -> Bool {
        if featureFlagger.isFeatureOn(.icsCalendarLinks), isICS(mimeType: mimeType, url: url, filename: filename) {
            return true
        }
        if featureFlagger.isFeatureOn(.vcardContactLinks), isVCard(mimeType: mimeType, url: url, filename: filename) {
            return true
        }
        return false
    }

    private static func isICS(mimeType: MIMEType, url: URL?, filename: String?) -> Bool {
        if mimeType == .calendar { return true }
        if url?.pathExtension.lowercased() == "ics" { return true }
        if filename?.lowercased().hasSuffix(".ics") == true { return true }
        return false
    }

    private static func isVCard(mimeType: MIMEType, url: URL?, filename: String?) -> Bool {
        if mimeType == .contact { return true }
        return hasVCardFileExtension(url: url, filename: filename)
    }

    /// Matches `.vcf`/`.vcard` by URL path extension or filename suffix (case-insensitive). Shared
    /// with the Downloads-list entry point (`CompleteDownloadRowViewModel`) so both define "is this a
    /// vCard filename" the same way.
    static func hasVCardFileExtension(url: URL?, filename: String?) -> Bool {
        if let pathExtension = url?.pathExtension.lowercased(), pathExtension == "vcf" || pathExtension == "vcard" {
            return true
        }
        if let lowercasedFilename = filename?.lowercased(),
           lowercasedFilename.hasSuffix(".vcf") || lowercasedFilename.hasSuffix(".vcard") {
            return true
        }
        return false
    }
}
