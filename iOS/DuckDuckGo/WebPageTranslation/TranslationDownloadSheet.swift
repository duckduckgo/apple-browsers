//
//  TranslationDownloadSheet.swift
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
import DuckUI
import MetricBuilder
import SwiftUI
import UIKit
import WebPageTranslation

/// Asks before downloading the language pack a translation needs, and shows its size.
enum TranslationDownloadSheet {

    struct Strings: Equatable {
        let title: String
        let message: String
        let size: String
    }

    static func text(for offer: TranslationOffer, locale: Locale) -> Strings {
        let language = locale.localizedString(forLanguageCode: offer.source) ?? offer.source
        let size = ByteCountFormatter.string(fromByteCount: offer.downloadBytes, countStyle: .file)
        return Strings(title: UserText.translationDownloadSheetTitle(language: language),
                    message: UserText.translationDownloadSheetMessage(language: language),
                    size: UserText.translationDownloadSheetSize(size))
    }

    /// A sheet sized to its content. `onDownload` runs when the user taps Download and Translate.
    @MainActor
    static func makeController(for offer: TranslationOffer, onDownload: @escaping () -> Void) -> UIViewController {
        let view = TranslationDownloadSheetView(text: text(for: offer, locale: .current), onDownload: onDownload)
        let controller = TranslationDownloadSheetController(rootView: view)
        controller.modalPresentationStyle = .pageSheet
        controller.disableSafeArea()
        controller.view.backgroundColor = UIColor(designSystemColor: .backgroundSheets)
        if let sheet = controller.sheetPresentationController {
            if #available(iOS 16, *) {
                sheet.detents = [.custom { [weak controller] context in
                    controller?.fittingHeight(upTo: context.maximumDetentValue)
                }]
            } else {
                sheet.detents = [.medium()]
            }
            if #unavailable(iOS 26) {
                sheet.preferredCornerRadius = SheetMetrics.cornerRadius
            }
        }
        return controller
    }
}

/// Measures its content for the sheet's height, and asks for a new height when the width or text size changes it.
final class TranslationDownloadSheetController: UIHostingController<TranslationDownloadSheetView> {

    private var lastHeight: CGFloat?

    /// A custom detent's height leaves out the bottom safe area, which the sheet adds back, so it's taken off here.
    func fittingHeight(upTo maximum: CGFloat) -> CGFloat {
        let window = view.window ?? presentingViewController?.view.window
        let width = view.bounds.width > 0 ? view.bounds.width : (window?.bounds.width ?? UIScreen.main.bounds.width)
        let contentHeight = sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height
        return min(contentHeight - (window?.safeAreaInsets.bottom ?? 0), maximum)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard #available(iOS 16, *) else { return }
        let height = sizeThatFits(in: CGSize(width: view.bounds.width, height: .greatestFiniteMagnitude)).height
        guard height != lastHeight else { return }
        lastHeight = height
        sheetPresentationController?.invalidateDetents()
    }
}

struct TranslationDownloadSheetView: View {

    let text: TranslationDownloadSheet.Strings
    let onDownload: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if #available(iOS 16, *) {
                // Scrolls only when large text makes the content taller than the sheet can be.
                ViewThatFits(in: .vertical) {
                    content
                    ScrollView { content }
                }
            } else {
                ScrollView { content }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .overlay(alignment: .topTrailing) { closeButton }
        // Pinned to the top, so any height the sheet adds stays below the button.
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var content: some View {
        VStack(spacing: 32) {
            VStack(spacing: 4) {
                Image(uiImage: DesignSystemImages.Color.Size96.translate)
                    .accessibilityHidden(true)

                VStack(spacing: 4) {
                    Text(text.title)
                        .daxTitle3()
                        .foregroundColor(Color(designSystemColor: .textPrimary))
                        .accessibilityAddTraits(.isHeader)

                    VStack(spacing: 8) {
                        Text(text.message)
                        Text(text.size)
                    }
                    .daxBodyRegular()
                    .foregroundColor(Color(designSystemColor: .textSecondary))
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
            }

            Button(UserText.translationDownloadSheetButton) {
                onDownload()
                dismiss()
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("TranslationDownloadSheet.download")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 32)
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            // With the style's own padding, a 40 pt circle, as in the design.
            Image(uiImage: DesignSystemImages.Glyphs.Size24.close)
                .padding(4)
        }
        .buttonStyle(CloseButtonStyle())
        .accessibilityLabel(UserText.translationDownloadSheetClose)
        // With the style's outer padding, 20 pt from the sheet's top and trailing edges.
        .padding(.top, 16)
        .padding(.trailing, 16)
    }
}

#Preview {
    let text = TranslationDownloadSheet.text(for: TranslationOffer(source: "es",
                                                                   target: "en",
                                                                   pairID: "es-en",
                                                                   downloadBytes: 23_000_000),
                                             locale: .current)
    return Color.clear.sheet(isPresented: .constant(true)) {
        TranslationDownloadSheetView(text: text, onDownload: {})
    }
}
