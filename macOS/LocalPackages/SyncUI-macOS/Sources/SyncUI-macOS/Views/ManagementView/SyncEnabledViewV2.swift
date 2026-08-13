//
//  SyncEnabledViewV2.swift
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

import AppKit
import SwiftUI
import SwiftUIExtensions
import DesignResourcesKit
import DesignResourcesKitIcons
import PreferencesUI_macOS

#if DEBUG
import PreviewSnapshots
#endif

struct SyncEnabledViewV2<ViewModel>: View where ViewModel: ManagementViewModel {
    @EnvironmentObject var model: ViewModel

    var body: some View {
        // Errors
        VStack(alignment: .leading, spacing: 16) {
            syncUnavailableView()
            if model.isSyncPaused {
                syncPaused()
            }
            if model.isSyncBookmarksPaused {
                syncPaused(for: .bookmarks)
            }
            if model.isSyncCredentialsPaused {
                syncPaused(for: .credentials)
            }
            if model.isSyncCreditCardsPaused {
                syncPaused(for: .creditCards)
            }
            if model.isSyncIdentitiesPaused {
                syncPaused(for: .identities)
            }
            if !model.invalidBookmarksTitles.isEmpty {
                syncHasInvalidItems(for: .bookmarks)
            }
            if !model.invalidCredentialsTitles.isEmpty {
                syncHasInvalidItems(for: .credentials)
            }
            if !model.invalidCreditCardsTitles.isEmpty {
                syncHasInvalidItems(for: .creditCards)
            }
            if !model.invalidIdentitiesTitles.isEmpty {
                syncHasInvalidItems(for: .identities)
            }
        }

        // Intro text
        SyncUIViewsV2.TextDetailSecondaryLeftAligned(text: model.isAIChatSyncEnabled ? UserText.syncEnabledFooterV2 : UserText.syncEnabledFooterWithoutAIChatV2)

        // My Devices
        PreferencePaneSection(UserText.myDevicesV2) {
            SyncedDevicesViewV2<ViewModel>()
                .environmentObject(model)

            SyncUIViewsV2.TextDetailSecondary(text: UserText.myDevicesFooterV2)
        }

        // Bookmarks
        PreferencePaneSection(UserText.bookmarksSectionTitleV2) {
            bookmarkOption(title: UserText.shareFavoritesOptionTitleV2,
                           caption: UserText.shareFavoritesOptionCaptionV2,
                           isOn: $model.isUnifiedFavoritesEnabled)

            bookmarkOption(title: UserText.fetchFaviconsOptionTitleV2,
                           caption: UserText.fetchFaviconsOptionCaptionV2,
                           isOn: $model.isFaviconsFetchingEnabled)
        }

        // Recovery Code
        PreferencePaneSection(UserText.recoveryCodeSectionTitleV2) {
            recoverySection()
        }

        // Turn Off and Delete Data
        PreferencePaneSection {
            Button {
                model.presentDeleteAccount()
            } label: {
                Text(UserText.turnOffAndDeleteServerDataV2)
                    .foregroundColor(Color(designSystemColor: .destructivePrimary))
            }
        }
    }

    private func bookmarkOption(title: String, caption: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Toggle(isOn: isOn) {
                EmptyView()
            }
            .labelsHidden()
            .toggleStyle(.checkbox)
            .rebrandedControlTint()
            .accessibilityLabel(Text(title))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                SyncUIViewsV2.TextCaption(text: caption)
            }
            Spacer()
        }
    }

    private func recoverySection() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            recoveryInstructionsRow()
            recoveryInstructionsFooter()
        }
    }

    private func recoveryInstructionsRow() -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(UserText.recoveryInstructionsV2)
                .fixMultilineScrollableText()
            Spacer()
            Button(UserText.downloadRecoveryCodeButtonV2, action: model.saveRecoveryPDF)
        }
    }

    private func recoveryInstructionsFooter() -> some View {
        SyncUIViewsV2.TextDetailSecondary(text: UserText.recoveryInstructionsFooterV2)
    }

    @ViewBuilder
    func syncPaused() -> some View {
        if let title = model.syncPausedTitle,
           let message = model.syncPausedMessage,
           let buttonTitle = model.syncPausedButtonTitle {
            if let action = model.syncPausedButtonAction {
                SyncWarningMessage(title: title, message: message, buttonTitle: buttonTitle) {
                    action()
                }
            } else {
                SyncWarningMessage(title: title, message: message, buttonTitle: buttonTitle)
            }
        }
    }

    @ViewBuilder
    func syncPaused(for itemType: LimitedItemType) -> some View {
        var title: String? {
            switch itemType {
            case .bookmarks:
                return model.syncBookmarksPausedTitle
            case .credentials:
                return model.syncCredentialsPausedTitle
            case .creditCards:
                return model.syncCreditCardsPausedTitle
            case .identities:
                return model.syncIdentitiesPausedTitle
            }
        }
        var message: String? {
            switch itemType {
            case .bookmarks:
                return model.syncBookmarksPausedMessage
            case .credentials:
                return model.syncCredentialsPausedMessage
            case .creditCards:
                return model.syncCreditCardsPausedMessage
            case .identities:
                return model.syncIdentitiesPausedMessage
            }
        }
        var buttonTitle: String? {
            switch itemType {
            case .bookmarks:
                return model.syncBookmarksPausedButtonTitle
            case .credentials:
                return model.syncCredentialsPausedButtonTitle
            case .creditCards:
                return model.syncCreditCardsPausedButtonTitle
            case .identities:
                return model.syncIdentitiesPausedButtonTitle
            }
        }

        if let title,
           let message,
           let buttonTitle {
            if let action = model.syncPausedButtonAction {
                SyncWarningMessage(title: title, message: message, buttonTitle: buttonTitle) {
                    action()
                }
            } else {
                SyncWarningMessage(title: title, message: message, buttonTitle: buttonTitle)
            }
        }
    }

    @ViewBuilder
    func syncHasInvalidItems(for itemType: LimitedItemType) -> some View {
        var title: String {
            switch itemType {
            case .bookmarks:
                return UserText.invalidBookmarksPresentTitle
            case .credentials:
                return UserText.invalidCredentialsPresentTitle
            case .creditCards:
                return UserText.invalidCreditCardsPresentTitle
            case .identities:
                return UserText.invalidIdentitiesPresentTitle
            }
        }
        var description: String {
            switch itemType {
            case .bookmarks:
                assert(!model.invalidBookmarksTitles.isEmpty)
                let firstInvalidBookmarkTitle = model.invalidBookmarksTitles.first ?? ""
                return UserText.invalidBookmarksPresentDescription(firstInvalidBookmarkTitle, numberOfInvalidItems: model.invalidBookmarksTitles.count)

            case .credentials:
                assert(!model.invalidCredentialsTitles.isEmpty)
                let firstInvalidCredentialTitle = model.invalidCredentialsTitles.first ?? ""
                return UserText.invalidCredentialsPresentDescription(firstInvalidCredentialTitle, numberOfInvalidItems: model.invalidCredentialsTitles.count)

            case .creditCards:
                assert(!model.invalidCreditCardsTitles.isEmpty)
                let firstInvalidCreditCardTitle = model.invalidCreditCardsTitles.first ?? ""
                return UserText.invalidCreditCardsPresentDescription(firstInvalidCreditCardTitle, numberOfInvalidItems: model.invalidCreditCardsTitles.count)

            case .identities:
                assert(!model.invalidIdentitiesTitles.isEmpty)
                let firstInvalidIdentityTitle = model.invalidIdentitiesTitles.first ?? ""
                return UserText.invalidIdentitiesPresentDescription(firstInvalidIdentityTitle, numberOfInvalidItems: model.invalidIdentitiesTitles.count)
            }
        }
        var actionTitle: String {
            switch itemType {
            case .bookmarks:
                return UserText.bookmarksLimitExceededAction
            case .credentials:
                return UserText.credentialsLimitExceededAction
            case .creditCards:
                return UserText.creditCardsLimitExceededAction
            case .identities:
                return UserText.identitiesLimitExceededAction
            }
        }
        SyncWarningMessage(title: title, message: description, buttonTitle: actionTitle) {
            switch itemType {
            case .bookmarks:
                model.manageBookmarks()
            case .credentials:
                model.manageLogins()
            case .creditCards:
                model.manageCreditCards()
            case .identities:
                model.manageIdentities()
            }
        }
    }

    @ViewBuilder
    fileprivate func syncUnavailableView() -> some View {
        if model.isDataSyncingAvailable {
            EmptyView()
        } else {
            if model.isAppVersionNotSupported {
                SyncWarningMessage(title: UserText.syncPausedTitle, message: UserText.syncUnavailableMessageUpgradeRequired)
            } else {
                SyncWarningMessage(title: UserText.syncPausedTitle, message: UserText.syncUnavailableMessage)
            }
        }
    }

    enum LimitedItemType {
        case bookmarks
        case credentials
        case creditCards
        case identities
    }
}

#if DEBUG
struct SyncEnabledViewV2_Previews: PreviewProvider {
    typealias State = PreviewManagementViewModel

    static var previews: some View {
        snapshots.previews
    }

    static let snapshots = PreviewSnapshots<State>(
        configurations: [
            .init(name: "Enabled", state: .enabled),
            .init(name: "Loading devices", state: .enabledLoadingDevices),
            .init(name: "Sync paused", state: .syncPaused)
        ],
        configure: { model in
            DesignSystemRebrand.isAppRebranded = { true }
            return ScrollView {
                PreferencePane {
                    StatusIndicatorView(status: .on, isLarge: true)
                    SyncEnabledViewV2<PreviewManagementViewModel>()
                        .environmentObject(model)
                }
                .padding()
            }
            .frame(width: 600, height: 900)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    )
}
#endif
