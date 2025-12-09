//
//  DataImportSummaryDetailView.swift
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

import SwiftUI
import BrowserServicesKit
import DesignResourcesKitIcons
import DesignResourcesKit
import UIComponents

/// Displays the summary of a data import operation. Currently only used for password imports.
/// Shows the number of items imported, duplicated, and failed. It also displays the 
/// details of the duplicated and failed items.
///
struct DataImportSummaryDetailView: View {
    typealias ImportItem = DataImport.DataImportItem

    let result: DataImportResult<DataImport.DataTypeSummary>

    var body: some View {
        VStack(spacing: 0) {
            headerView
                .padding(.horizontal, Metrics.outerPadding)
                .padding(.top, Metrics.outerPadding)
                .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.mainStackViewSpacing) {
                    summaryView

                    if case .success(let summary) = result {
                        if summary.duplicate > 0 {
                            duplicatesSection(summary: summary)
                        }

                        if summary.failed > 0 {
                            failedSection(summary: summary)
                        }
                    }
                }
                .padding(.horizontal, Metrics.outerPadding)
            }
            .padding(.bottom, Metrics.outerPadding)
        }
        .frame(maxHeight: 600)
    }

    private var headerView: some View {
        HStack {
            Text(title)
                .font(.system(size: Metrics.fontSize, weight: .bold))
                .foregroundColor(.primary)
            Spacer()
        }
    }

    /// Displays a summary of the import operation. e.g. "Total Passwords Imported: 1293 / 1300"
    ///
    private var summaryView: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(.blackWhite5))
                .frame(width: Metrics.iconContainerSize, height: Metrics.iconContainerSize)
                .overlay(
                    Image(nsImage: iconImage)
                        .resizable()
                        .frame(width: Metrics.iconSize, height: Metrics.iconSize)
                )

            Text(summaryText)
                .font(.system(size: Metrics.fontSize))
                .foregroundColor(.primary)

            Spacer()

            iconWithWhiteBackground(
                image: DesignSystemImages.Glyphs.Size20.checkSolid,
                foregroundColor: Color(designSystemColor: .alertGreen)
            )
        }
        .padding(.horizontal, Metrics.sectionInnerPadding)
        .frame(height: Metrics.sectionHeaderHeight)
        .borderedBackground()
    }

    /// Displays any duplicated items in the summary.
    ///
    private func duplicatesSection(summary: DataImport.DataTypeSummary) -> some View {
        return sectionView(
            items: summary.duplicateItems,
            header: {
                Text(UserText.importSummaryDuplicatesSkipped(summary.duplicate))
                    .font(.system(size: Metrics.fontSize, weight: .medium))
                    .foregroundColor(.primary)
            },
            rowContent: { item in
                duplicateRow(item: item)
            }
        )
    }

    @ViewBuilder
    private func duplicateRow(item: ImportItem) -> some View {
        if case .password(_, let domain, let username, _) = item {
            duplicateRowContent(
                icon: DesignSystemImages.Glyphs.Size16.globe,
                content: {
                    primarySecondaryText(primary: domain, secondary: " (\(username))")
                }
            )
        }
    }

    /// Creates a duplicate row with an icon and content.
    ///
    private func duplicateRowContent<Content: View>(
        icon: NSImage,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 8) {
            Image(nsImage: icon)
                .frame(width: Metrics.iconContainerSize, height: Metrics.iconSize)
                .foregroundColor(.primary)

            content()

            Spacer()
        }
    }

    /// Displays any failed items in the summary.
    ///
    private func failedSection(summary: DataImport.DataTypeSummary) -> some View {
        return sectionView(
            items: summary.failedItems,
            header: {
                HStack {
                    Text(UserText.importSummaryFailedToImport(summary.failed))
                        .font(.system(size: Metrics.fontSize, weight: .medium))
                        .foregroundColor(.primary)

                    Spacer()

                    iconWithWhiteBackground(
                        image: DesignSystemImages.Glyphs.Size24.exclamationSolid,
                        foregroundColor: Color(designSystemColor: .destructivePrimary)
                    )
                }
            },
            rowContent: { item in
                failedRow(item: item)
            }
        )
    }

    private func failedRow(item: ImportItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            failedRowText(item: item)
                .font(.system(size: Metrics.fontSize))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    private func failedRowText(item: ImportItem) -> Text {
        guard case .password(let title, let domain, let username, let errorMessage) = item else {
            return Text("")
        }

        func valueOrNone(_ value: String?) -> String {
            guard let value, value.isEmpty == false else { return " \(UserText.none) " }
            return " \(value) "
        }

        return primarySecondaryText(primary: UserText.importSummaryDetailsFailedItemTitle, secondary: valueOrNone(title))
             + primarySecondaryText(primary: UserText.importSummaryDetailsFailedItemHost, secondary: valueOrNone(domain))
             + primarySecondaryText(primary: UserText.importSummaryDetailsFailedItemUser, secondary: valueOrNone(username))
             + primarySecondaryText(primary: UserText.importSummaryDetailsFailedItemError, secondary: valueOrNone(errorMessage))
    }

    /// Creates a Text with primary (title) and optional secondary (value) text.
    ///
    private func primarySecondaryText(primary: String, secondary: String? = nil) -> Text {
        var result = Text(primary)
            .font(.system(size: Metrics.fontSize))
            .foregroundColor(.primary)

        if let secondary {
            // swiftlint:disable shorthand_operator
            result = result + Text(secondary)
                .font(.system(size: Metrics.fontSize))
                .foregroundColor(.secondary)
            // swiftlint:enable shorthand_operator
        }

        return result
    }

    /// Creates an icon with a white circular background to make transparent parts appear white.
    ///
    private func iconWithWhiteBackground(image: NSImage, foregroundColor: Color) -> some View {
        ZStack {
            Circle()
                .fill(Color.white)
                .frame(width: Metrics.iconSize - 2, height: Metrics.iconSize - 2)

            Image(nsImage: image)
                .renderingMode(.template)
                .frame(width: Metrics.iconSize, height: Metrics.iconSize)
                .foregroundColor(foregroundColor)
        }
    }

    /// Creates a section view with a header, separator, and list of items.
    ///
    private func sectionView<RowContent: View, HeaderView: View>(
        items: [ImportItem],
        @ViewBuilder header: () -> HeaderView,
        @ViewBuilder rowContent: @escaping (ImportItem) -> RowContent
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header()
                .frame(height: Metrics.sectionHeaderHeight)

            lineSeparator

            LazyVStack(alignment: .leading, spacing: Metrics.innerRowSpacing) {
                ForEach(items.indices, id: \.self) { index in
                    rowContent(items[index])
                }
            }
            .padding(.vertical, Metrics.sectionInnerPadding)
        }
        .padding(.horizontal, Metrics.sectionInnerPadding)
        .borderedBackground()
    }

    private var lineSeparator: some View {
        Divider()
            .foregroundColor(.secondary)
    }

    private var title: String {
        UserText.importSummaryDetailsPasswordsTitle
    }

    private var iconImage: NSImage {
        DesignSystemImages.Glyphs.Size16.keyLogin
    }

    private var summaryText: String {
        var successful = 0
        var total = 0

        if case .success(let summary) = result {
            successful = summary.successful
            total = summary.successful + summary.duplicate + summary.failed
        }

        return "\(UserText.importSummaryDetailsTotalPasswordsImported) \(successful) / \(total)"
    }

    private enum Metrics {
        static let sectionInnerPadding: CGFloat = 10
        static let mainStackViewSpacing: CGFloat = 20
        static let outerPadding: CGFloat = 20
        static let iconSize: CGFloat = 16.0
        static let iconContainerSize: CGFloat = 24.0
        static let sectionHeaderHeight: CGFloat = 44.0
        static let innerRowSpacing: CGFloat = 8.0
        static let fontSize: CGFloat = 13.0
    }
}

private struct CloseButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(
                configuration.isPressed
                ? Color(designSystemColor: .buttonsPrimaryPressed)
                : Color(designSystemColor: .buttonsPrimaryDefault)
            )
            .foregroundColor(.white)
            .cornerRadius(6)
    }
}

#if DEBUG
#Preview("Passwords - Duplicates & Failures") {
    DataImportSummaryDetailView(
        result: .success(.init(
            successful: 1293,
            duplicateItems: [
                .password(title: "Example Site", domain: "example.com", username: "user1", errorMessage: nil),
                .password(title: "My Account", domain: "test.com", username: "user2", errorMessage: nil),
                .password(title: nil, domain: "login.com", username: "admin", errorMessage: nil)
            ],
            failedItems: [
                .password(title: "Failed Site", domain: "failed.com", username: "user3", errorMessage: "Encryption error occurred"),
                .password(title: "Secure Login", domain: "secure.example.com", username: "user4", errorMessage: "Invalid password format")
            ]
        ))
    )
    .frame(width: 600, height: 700)
}

#Preview("Passwords - Only Failures") {
    DataImportSummaryDetailView(
        result: .success(.init(
            successful: 50,
            duplicateItems: [],
            failedItems: [
                .password(title: "Failed Site 1", domain: "failed1.com", username: "user1", errorMessage: "Network error"),
                .password(title: "Failed Site 2", domain: "failed2.com", username: "user2", errorMessage: "Decryption failed"),
                .password(title: nil, domain: "failed3.com", username: "user3", errorMessage: "Invalid format")
            ]
        ))
    )
    .frame(width: 600, height: 500)
}

#Preview("Passwords – Only Duplicates") {
    DataImportSummaryDetailView(
        result: .success(.init(
            successful: 0,
            duplicateItems: [
                .password(title: "Example Site", domain: "example.com", username: "user1", errorMessage: nil),
                .password(title: "My Account", domain: "test.com", username: "user2", errorMessage: nil),
                .password(title: nil, domain: "login.com", username: "admin", errorMessage: nil)
            ],
            failedItems: []
        ))
    )
    .frame(width: 600, height: 500)
}

#Preview("Passwords - Only Successes") {
    DataImportSummaryDetailView(
        result: .success(.init(
            successful: 1293,
            duplicateItems: [],
            failedItems: []
        ))
    )
    .frame(width: 600, height: 500)
}
#endif
