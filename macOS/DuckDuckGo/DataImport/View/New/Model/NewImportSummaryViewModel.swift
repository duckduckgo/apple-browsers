//
//  NewImportSummaryViewModel.swift
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

import AppKit
import Combine
import BrowserServicesKit
import DesignResourcesKitIcons
import DesignResourcesKit

@MainActor
final class NewImportSummaryViewModel: ObservableObject {
    enum SummaryItem: Equatable, Identifiable {
        var id: String {
            switch self {
            case .success(let item):
                return item.id
            case .failure(let title):
                return title
            }
        }

        case success(SuccessItem)
        case failure(title: String)

        mutating func setShortcutState(_ isOn: Bool) {
            guard case .success(var item) = self else { return }
            if var shortcut = item.shortcut {
                shortcut.isOn = isOn
                item.shortcut = shortcut
                self = .success(item)
            }
        }
    }

    struct SuccessItem: Identifiable, Equatable {
        var type: DataImport.DataType
        var id: String {
            type.rawValue
        }

        var image: NSImage
        var primaryText: String
        var duplicateText: String?
        var failureText: String?
        var shortcut: ShortcutItem?
    }

    struct ShortcutItem: Equatable {
        var title: String
        var isOn: Bool = false
    }

    @Published var items: [SummaryItem]
    let shouldShowFeedbackView: Bool
    let shouldShowSuccessImage: Bool

    private let prefs: AppearancePreferences
    private let pinningManager: PinningManager

    private var showBookmarksBarStatus: Bool {
        didSet {
            prefs.showBookmarksBar = showBookmarksBarStatus
        }
    }

    private var showPasswordsPinnedStatus: Bool {
        didSet {
            if showPasswordsPinnedStatus {
                pinningManager.pin(.autofill)
                NotificationCenter.default.post(name: .passwordsAutoPinned, object: nil)
            } else {
                pinningManager.unpin(.autofill)
            }
        }
    }

    init(summary: DataImportSummary, prefs: AppearancePreferences? = nil, pinningManager: PinningManager) {
        self.prefs = prefs ?? NSApp.delegateTyped.appearancePreferences
        self.pinningManager = pinningManager

        showBookmarksBarStatus = self.prefs.showBookmarksBar
        showPasswordsPinnedStatus = pinningManager.isPinned(.autofill)

        self.items = summary.sorted {
            $0.key < $1.key
        }.compactMap { dataType, result in
            Self.createSummaryItem(for: dataType, result: result)
        }

        shouldShowFeedbackView = summary.contains { element in
            if case .failure = element.value {
                return true
            } else {
                return false
            }
        }

        shouldShowSuccessImage = !shouldShowFeedbackView
        updateShortcutsState()
    }

    func didTriggerShortcut(on summaryItem: SummaryItem, isOn: Bool) {
        guard case .success(let successItem) = summaryItem else {
            return
        }
        switch successItem.type {
        case .bookmarks:
            showBookmarksBarStatus = isOn
        case .passwords:
            showPasswordsPinnedStatus = isOn
        case .creditCards:
            break
        }
        updateShortcutsState()
    }

    private func updateShortcutsState() {
        for index in items.indices {
            guard case .success(let item) = items[index] else {
                continue
            }
            switch item.type {
            case .bookmarks:
                items[index].setShortcutState(showBookmarksBarStatus)
            case .passwords:
                items[index].setShortcutState(showPasswordsPinnedStatus)
            case .creditCards:
                break
            }
        }
    }

    private static func createSummaryItem(for dataType: DataImport.DataType, result: DataImportResult<DataImport.DataTypeSummary>) -> SummaryItem {
        guard case .success(let typeSummary) = result else {
            switch dataType {
            case .bookmarks:
                return .failure(title: UserText.importCouldNotImportBookmarks)
            case .passwords:
                return .failure(title: UserText.importCouldNotImportPasswords)
            case .creditCards:
                return .failure(title: UserText.importCouldNotImportCreditCards)
            }
        }

        let image = image(for: dataType)
        let primaryText = primaryText(for: dataType, summary: typeSummary)
        let duplicateText = duplicateText(from: typeSummary)
        let failureText = failureText(from: typeSummary)
        let shortcut = shortcutItem(for: dataType)

        let successItem = SuccessItem(
            type: dataType,
            image: image,
            primaryText: primaryText,
            duplicateText: duplicateText,
            failureText: failureText,
            shortcut: shortcut
        )

        return .success(successItem)
    }

    private static func image(for dataType: DataImport.DataType) -> NSImage {
        switch dataType {
        case .bookmarks:
            return DesignSystemImages.Color.Size24.bookmarkCheck
        case .passwords:
            return DesignSystemImages.Color.Size24.keyCheck
        case .creditCards:
            return DesignSystemImages.Color.Size24.creditCardCheck
        }
    }

    private static func primaryText(for dataType: DataImport.DataType, summary: DataImport.DataTypeSummary) -> String {
        let total = summary.successful + summary.duplicateItems.count + summary.failedItems.count
        let allImported = summary.duplicateItems.isEmpty && summary.failedItems.isEmpty

        if allImported {
            switch dataType {
            case .bookmarks:
                return UserText.importSummaryBookmarksImported(summary.successful)
            case .passwords:
                return UserText.importSummaryPasswordsImported(summary.successful)
            case .creditCards:
                return UserText.importSummaryCreditCardsImported(summary.successful)
            }
        } else {
            switch dataType {
            case .bookmarks:
                return UserText.importSummaryBookmarksImportedPartial(summary.successful, total)
            case .passwords:
                return UserText.importSummaryPasswordsImportedPartial(summary.successful, total)
            case .creditCards:
                return UserText.importSummaryCreditCardsImportedPartial(summary.successful, total)
            }
        }
    }

    private static func duplicateText(from summary: DataImport.DataTypeSummary) -> String? {
        guard summary.duplicateItems.isEmpty == false else { return nil }
        return UserText.importSummaryDuplicatesSkipped(summary.duplicateItems.count)
    }

    private static func failureText(from summary: DataImport.DataTypeSummary) -> String? {
        guard summary.failedItems.isEmpty == false else { return nil }
        return UserText.importSummaryFailedToImport(summary.failedItems.count)
    }

    private static func shortcutItem(for dataType: DataImport.DataType) -> ShortcutItem? {
        switch dataType {
        case .bookmarks:
            return ShortcutItem(title: UserText.importShortcutsBookmarksTitle, isOn: false)
        case .passwords:
            return ShortcutItem(title: UserText.importShortcutsPasswordsTitle, isOn: false)
        case .creditCards:
            return nil
        }
    }
}
