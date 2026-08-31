//
//  SitePermissionsSheetView.swift
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

import DesignResourcesKit
import DesignResourcesKitIcons
import MetricBuilder
import SwiftUI
import UIComponents
import UIKit

public struct SitePermissionsSheetView: View {

    private enum Constants {
        static let rowHorizontalInset: CGFloat = 16
        static let rowVerticalInset: CGFloat = 14
        static let iconSpacing: CGFloat = 16
        static let copySpacing: CGFloat = 8
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject private var viewModel: SitePermissionsSheetViewModel

    public init(viewModel: SitePermissionsSheetViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Group {
            if #available(iOS 16.0, *) {
                ViewThatFits(in: .vertical) {
                    sheetContent
                    ScrollView { sheetContent }
                }
            } else if dynamicTypeSize.isAccessibilitySize {
                ScrollView { sheetContent }
            } else {
                sheetContent
            }
        }
        .background(Color(designSystemColor: .backgroundSheets).ignoresSafeArea())
        .accessibilityIdentifier("SitePermissions.Sheet")
    }

    private var sheetContent: some View {
        VStack(alignment: .leading, spacing: SheetMetrics.contentSpacing) {
            header

            if !viewModel.rows.isEmpty {
                permissionRows
            }

            switch viewModel.state {
            case .permissionsOnly:
                VStack(alignment: .leading, spacing: Constants.copySpacing) {
                    reloadCaption
                    actionCard(includesRemove: true, includesSystemSettings: false)
                }
            case .permissionsAndReminder:
                VStack(alignment: .leading, spacing: Constants.copySpacing) {
                    actionCard(includesRemove: true, includesSystemSettings: true)
                    reminder
                }
            case .reminderOnly:
                VStack(alignment: .leading, spacing: Constants.copySpacing) {
                    actionCard(includesRemove: false, includesSystemSettings: true)
                    reminder
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, SheetMetrics.contentHorizontalPadding)
        .padding(.top, SheetMetrics.contentSpacing)
        .padding(.bottom, SheetMetrics.contentBottomPadding)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(viewModel.title)
                .daxBodyBold()
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .lineLimit(1)
                .truncationMode(.middle)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("SitePermissions.Sheet.Title")

            Spacer(minLength: 0)

            Button(action: viewModel.dismiss) {
                Image(uiImage: DesignSystemImages.Glyphs.Size24.close)
            }
            .buttonStyle(CloseButtonStyle())
            .accessibilityLabel(UserText.PermissionManagement.close)
            .accessibilityIdentifier("SitePermissions.Sheet.Close")
        }
    }

    private var permissionRows: some View {
        VStack(spacing: 0) {
            ForEach(Array(viewModel.rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 {
                    Color(designSystemColor: .lines)
                        .frame(height: 1)
                        .padding(.leading, Constants.rowHorizontalInset + 24 + Constants.iconSpacing)
                        .padding(.trailing, Constants.rowHorizontalInset)
                }
                permissionRow(row)
            }
        }
        .background(Color(designSystemColor: .surfaceTertiary))
        .clipShape(RoundedRectangle(cornerRadius: ContainerMetrics.cornerRadius, style: .continuous))
    }

    private func permissionRow(_ row: SitePermissionsSheetViewModel.Row) -> some View {
        Menu {
            ForEach(row.options, id: \.self) { option in
                Button {
                    viewModel.select(option, for: row.permissionType)
                } label: {
                    if option == row.selectedOption {
                        Label(UserText.PermissionManagement.title(for: option), systemImage: "checkmark")
                    } else {
                        Text(UserText.PermissionManagement.title(for: option))
                    }
                }
            }
        } label: {
            CardItem(
                icon: CardItemIcon(position: .leadingColumn,
                                   visual: .image(permissionIcon(for: row).renderingMode(.template)),
                                   size: .size24,
                                   spacing: Constants.iconSpacing),
                title: CardItemText(row.title, font: .bodyRegular),
                trailing: .custom(HStack(spacing: 8) {
                    Text(row.stateText)
                        .daxBodyRegular()
                        .foregroundColor(Color(designSystemColor: .textSecondary))
                    Image(systemName: "chevron.up.chevron.down")
                        .foregroundColor(Color(designSystemColor: .iconsTertiary))
                }),
                accessibilityValue: row.accessibilityValue
            )
            .foregroundColor(iconColor(for: row))
            .padding(.horizontal, Constants.rowHorizontalInset)
            .padding(.vertical, Constants.rowVerticalInset)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded { _ in viewModel.beginEditing() })
        .accessibilityIdentifier("SitePermissions.Sheet.\(row.permissionType.rawValue.capitalized)")
    }

    private var reloadCaption: some View {
        Text(UserText.PermissionManagement.reloadCaption)
            .daxFootnoteRegular()
            .foregroundColor(Color(designSystemColor: .textSecondary))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Constants.rowHorizontalInset)
            .accessibilityIdentifier("SitePermissions.Sheet.ReloadCaption")
    }

    private func actionCard(includesRemove: Bool, includesSystemSettings: Bool) -> some View {
        let items = actionItems(includesRemove: includesRemove, includesSystemSettings: includesSystemSettings)
        return CardItemList(
            items,
            dividerLeadingInset: 0,
            contentInset: .init(horizontal: Constants.rowHorizontalInset, vertical: Constants.rowVerticalInset),
            onSelect: { index in
                guard items.indices.contains(index) else { return nil }
                if includesRemove, index == 0 {
                    return viewModel.removePermissions
                }
                return viewModel.openSystemSettings
            }
        )
        .background(Color(designSystemColor: .surfaceTertiary))
        .clipShape(RoundedRectangle(cornerRadius: ContainerMetrics.cornerRadius, style: .continuous))
        .accessibilityIdentifier("SitePermissions.Sheet.Actions")
    }

    private func actionItems(includesRemove: Bool, includesSystemSettings: Bool) -> [CardItem] {
        var items = [CardItem]()
        if includesRemove {
            items.append(CardItem(
                title: CardItemText(UserText.PermissionManagement.removePermissions,
                                    font: .bodyRegular,
                                    color: Color(designSystemColor: .accentPrimary))))
        }
        if includesSystemSettings {
            items.append(CardItem(
                title: CardItemText(UserText.PermissionManagement.goToSystemSettings,
                                    font: .bodyRegular,
                                    color: Color(designSystemColor: .accentPrimary)),
                trailing: .custom(Image(uiImage: DesignSystemImages.Glyphs.Size24.openIn)
                    .renderingMode(.template)
                    .foregroundColor(Color(designSystemColor: .accentPrimary)))))
        }
        return items
    }

    @ViewBuilder
    private var reminder: some View {
        if let reminderText = viewModel.reminderText {
            Text(reminderText)
                .daxFootnoteRegular()
                .foregroundColor(Color(designSystemColor: .textSecondary))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Constants.rowHorizontalInset)
                .accessibilityIdentifier("SitePermissions.Sheet.Reminder")
        }
    }

    private func permissionIcon(for row: SitePermissionsSheetViewModel.Row) -> Image {
        let image: UIImage
        switch (row.permissionType, row.iconState) {
        case (.camera, .outline):
            image = DesignSystemImages.Glyphs.Size24.video
        case (.camera, .blocked):
            image = DesignSystemImages.Glyphs.Size24.videoBlocked
        case (.camera, .solid), (.camera, .inUse):
            image = DesignSystemImages.Glyphs.Size24.videoSolid
        case (.microphone, .outline):
            image = DesignSystemImages.Glyphs.Size24.microphone
        case (.microphone, .blocked):
            image = DesignSystemImages.Glyphs.Size24.microphoneBlocked
        case (.microphone, .solid), (.microphone, .inUse):
            image = DesignSystemImages.Glyphs.Size24.microphoneSolid
        case (.location, .outline):
            image = DesignSystemImages.Glyphs.Size24.location
        case (.location, .blocked):
            image = DesignSystemImages.Glyphs.Size24.locationBlocked
        case (.location, .solid), (.location, .inUse):
            image = DesignSystemImages.Glyphs.Size24.locationSolid
        }
        return Image(uiImage: image)
    }

    private func iconColor(for row: SitePermissionsSheetViewModel.Row) -> Color {
        Color(designSystemColor: row.iconState == .inUse ? .buttonsDeleteGhostText : .icons)
    }
}
