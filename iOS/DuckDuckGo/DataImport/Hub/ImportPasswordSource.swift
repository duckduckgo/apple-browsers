//
//  ImportPasswordSource.swift
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

import SwiftUI
import DesignResourcesKitIcons

enum ImportPasswordSource: CaseIterable, Identifiable {
    case safari
    case chrome
    case passwordsApp
    case syncFromDuckDuckGo

    var id: String {
        switch self {
        case .passwordsApp: return "passwords_app"
        case .safari: return "safari"
        case .chrome: return "chrome"
        case .syncFromDuckDuckGo: return "sync_duckduckgo"
        }
    }

    enum Section: CaseIterable {
        case importFrom
        case syncFrom

        var title: String {
            switch self {
            case .importFrom:
                return UserText.importSourceSectionImportFrom
            case .syncFrom:
                return UserText.importSourceSectionSyncFrom
            }
        }

        var sources: [ImportPasswordSource] {
            switch self {
            case .importFrom:
                return [.safari, .chrome, .passwordsApp]
            case .syncFrom:
                return [.syncFromDuckDuckGo]
            }
        }
    }

    var title: String {
        switch self {
        case .passwordsApp:
            return UserText.importSourcePasswordsApp
        case .safari:
            return UserText.importSourceSafari
        case .chrome:
            return UserText.importSourceChrome
        case .syncFromDuckDuckGo:
            return UserText.importSourceSyncFromDuckDuckGo
        }
    }

    var listIcon: Image {
        switch self {
        case .passwordsApp:
            return Image(.passwordsMulticolor)
        case .safari:
            return Image(.safariMulticolor)
        case .chrome:
            return Image(.chromeMulticolor)
        case .syncFromDuckDuckGo:
            return Image(.appDuckDuckGo32)
        }
    }

    // MARK: - Detail Screen Content

    var detailIcon: Image {
        switch self {
        case .passwordsApp:
            return Image(uiImage: DesignSystemImages.Color.Size96.passwordsAppFeature)
        case .safari:
            return Image(uiImage: DesignSystemImages.Color.Size96.extensionSafari)
        case .chrome:
            return Image(uiImage: DesignSystemImages.Color.Size96.extensionChrome)
        case .syncFromDuckDuckGo:
            return Image(uiImage: DesignSystemImages.Color.Size96.syncPasswordsDesktop)
        }
    }

    var detailTitle: String {
        switch self {
        case .passwordsApp:
            return UserText.importDetailPasswordsTitle
        case .safari:
            return UserText.importDetailSafariTitle
        case .chrome:
            return UserText.importDetailChromeTitle
        case .syncFromDuckDuckGo:
            return title
        }
    }

    var hasDetailScreen: Bool {
        switch self {
        case .passwordsApp, .safari, .chrome:
            return true
        case .syncFromDuckDuckGo:
            return false
        }
    }

    var detailDescription: String {
        switch self {
        case .passwordsApp:
            return UserText.importDetailPasswordsDescription
        case .safari:
            return UserText.importDetailSafariDescription
        case .chrome:
            return UserText.importDetailChromeDescription
        case .syncFromDuckDuckGo:
            return ""
        }
    }

    var steps: [String] {
        switch self {
        case .passwordsApp:
            return [
                UserText.importDetailPasswordsStep1,
                UserText.importDetailPasswordsStep2,
                UserText.importDetailPasswordsStep3
            ]
        case .chrome:
            return [
                UserText.importDetailChromeStep1,
                UserText.importDetailChromeStep2,
                UserText.importDetailChromeStep3
            ]
        case .safari, .syncFromDuckDuckGo:
            return []
        }
    }

    var primaryButtonTitle: String? {
        switch self {
        case .safari:
            return UserText.importDetailSafariExportButton
        case .passwordsApp, .chrome, .syncFromDuckDuckGo:
            return nil
        }
    }

    var bottomSection: BottomSection? {
        switch self {
        case .safari:
            return .uploadFile
        case .passwordsApp, .chrome, .syncFromDuckDuckGo:
            return nil
        }
    }

    enum BottomSection {
        case uploadFile
    }
}
