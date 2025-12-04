//
//  NewFileImportView.swift
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

import Common
import SwiftUI
import UniformTypeIdentifiers
import os.log
import BrowserServicesKit
import DesignResourcesKit
import DesignResourcesKitIcons

@NewInstructionsView.InstructionsBuilder
func newFileImportMultipleTypeInstructionsBuilder(source: DataImport.Source) -> [NewInstructionsView.InstructionsItem] {
    switch source {
    case .safari, .safariTechnologyPreview:
        NSLocalizedString("import.zip.instructions.safari", value: """
        %d Open %@ **Safari → File → Export Browsing Data to File...**
        %d Choose **Bookmarks, Passwords,** and **Credit Cards**, → **Export** and save the file
        %d Upload the exported ZIP or CSV file to DuckDuckGo
        """, comment: """
        Instructions to import multiple data types exported as ZIP from Safari.
        %N$d - step number
        %2$@ - browser icon
        **bold text**; _italic text_
        """)
        (source.importSourceImage ?? DataImport.Source.safari.importSourceImage!).resizedToFaviconSize()
    case // browsers
         .brave, .chrome, .chromium, .coccoc,
         .edge, .firefox, .opera, .operaGX,
         .tor, .vivaldi, .yandex,
         // password managers
         .onePassword8, .onePassword7,
         .bitwarden, .lastPass,
         // file formats
         .csv, .bookmarksHTML, .fileImport:
        []
        assertionFailure("Invalid source for multi import")
    }
}

@NewInstructionsView.InstructionsBuilder
func newFileImportSingleTypeInstructionsBuilder(source: DataImport.Source, dataType: DataImport.DataType) -> [NewInstructionsView.InstructionsItem] {
    switch (source, dataType) {
    case (.chrome, .passwords):
        NSLocalizedString("import.csv.instructions.chrome.new.new", value: """
        %d Open **%s → %@ → Google Password Manager → Settings**
        %d Find **Export Passwords → click Download File** and save the file
        %d Upload the exported CSV file to DuckDuckGo
        """, comment: """
        Instructions to import Passwords as CSV from Google Chrome browser.
        %N$d - step number
        %2$s - browser name (Chrome)
        %3$@ - hamburger menu icon
        **bold text**; _italic text_
        """)
        source.importSourceName
        NSImage.menuVertical16

    case (.brave, .passwords):
        NSLocalizedString("import.csv.instructions.brave.new", value: """
        %d Open **%s → %@ → Password Manager → Settings**
        %d Find **Export Passwords → click Download File** and save the file
        %d Upload the exported CSV file to DuckDuckGo
        """, comment: """
        Instructions to import Passwords as CSV from Brave browser.
        %N$d - step number
        %2$s - browser name (Brave)
        %3$@ - hamburger menu icon
        **bold text**; _italic text_
        """)
        source.importSourceName
        NSImage.menuHamburger16

    case (.chromium, .passwords),
        (.edge, .passwords):
        NSLocalizedString("import.csv.instructions.chromium.new", value: """
        %d Open **%s → %@ → Password Manager → Settings**
        %d Find **Export Passwords → click Download File** and save the file
        %d Upload the exported CSV file to DuckDuckGo
        """, comment: """
        Instructions to import Passwords as CSV from Chromium-based browsers.
        %N$d - step number
        %2$s - browser name
        %3$@ - hamburger menu icon
        **bold text**; _italic text_
        """)
        source.importSourceName
        NSImage.menuVertical16

    case (.coccoc, .passwords):
        NSLocalizedString("import.csv.instructions.coccoc.new", value: """
        %d Type _coccoc://settings/passwords_ into the Address bar
        %d Click %@ (on the right from _Saved Passwords_) → **Export passwords** and save the file
        %d Upload the exported CSV file to DuckDuckGo
        """, comment: """
        Instructions to import Passwords as CSV from Cốc Cốc browser.
        %N$d - step number
        %3$@ - menu icon
        **bold text**; _italic text_
        """)
        NSImage.menuVertical16

    case (.opera, .passwords):
        NSLocalizedString("import.csv.instructions.opera.new", value: """
        %d Open **%s → View → Show Password Manager → Settings**
        %d Find **Export Passwords → Download File** and save the file
        %d Upload the exported CSV file to DuckDuckGo
        """, comment: """
        Instructions to import Passwords as CSV from Opera browser.
        %N$d - step number
        %2$s - browser name (Opera)
        **bold text**; _italic text_
        """)
        source.importSourceName

    case (.vivaldi, .passwords):
        NSLocalizedString("import.csv.instructions.vivaldi.new", value: """
        %d Type _chrome://settings/passwords_ into the Address bar
        %d Click %@ (on the right from _Saved Passwords_) → **Export passwords** and save the file
        %d Upload the exported CSV file to DuckDuckGo
        """, comment: """
        Instructions to import Passwords exported as CSV from Vivaldi browser.
        %N$d - step number
        %3$@ - menu button icon
        **bold text**; _italic text_
        """)
        NSImage.menuVertical16

    case (.operaGX, .passwords):
        NSLocalizedString("import.csv.instructions.operagx.new", value: """
        %d Open **%s → View → Show Password Manager → Settings**
        %d Click %@ (on the right from _Saved Passwords_) → **Export passwords** and save the file
        %d Upload the exported CSV file to DuckDuckGo
        """, comment: """
        Instructions to import Passwords as CSV from Opera GX browsers.
        %N$d - step number
        %2$s - browser name (Opera GX)
        %4$@ - menu button icon
        **bold text**; _italic text_
        """)
        source.importSourceName
        NSImage.menuVertical16

    case (.yandex, .passwords):
        NSLocalizedString("import.csv.instructions.yandex.new", value: """
        %d Open **%s →** %@ **→ Passwords and cards**
        %d Click %@ **→ Export passwords → To a text file (not secure) → Export** and save the file
        %d Upload the exported CSV file to DuckDuckGo
        """, comment: """
        Instructions to import Passwords as CSV from Yandex Browser.
        %N$d - step number
        %2$s - browser name (Yandex)
        %3$@ - hamburger menu icon
        %5$@ - vertical menu icon
        **bold text**; _italic text_
        """)
        source.importSourceName
        NSImage.menuHamburger16
        NSImage.menuVertical16

    case (.brave, .bookmarks),
        (.chrome, .bookmarks),
        (.chromium, .bookmarks),
        (.coccoc, .bookmarks),
        (.edge, .bookmarks):
        NSLocalizedString("import.html.instructions.chromium.new", value: """
        %d Open **%s → Bookmarks → Bookmark Manager**
        %d Click %@ **→ Export Bookmarks** and save the file
        %d Upload the exported HTML file to DuckDuckGo
        """, comment: """
        Instructions to import Bookmarks exported as HTML from Chromium-based browsers.
        %N$d - step number
        %2$s - browser name
        %4$@ - hamburger menu icon
        **bold text**; _italic text_
        """)
        source.importSourceName
        NSImage.menuVertical16

    case (.vivaldi, .bookmarks):
        NSLocalizedString("import.html.instructions.vivaldi.new", value: """
        %d Open **%s → File → Export Bookmarks…** and save the file
        %d Upload the exported HTML file to DuckDuckGo
        """, comment: """
        Instructions to import Bookmarks exported as HTML from Vivaldi browser.
        %N$d - step number
        %2$s - browser name (Vivaldi)
        **bold text**; _italic text_
        """)
        source.importSourceName

    case (.opera, .bookmarks):
        NSLocalizedString("import.html.instructions.opera.new", value: """
        %d Open **%s → Bookmarks → Bookmarks → Open full Bookmarks view…**
        %d Click **Import/Export… → Export Bookmarks** and save the file
        %d Upload the exported HTML file to DuckDuckGo
        """, comment: """
        Instructions to import Bookmarks exported as HTML from Opera browser.
        %N$d - step number
        %2$s - browser name (Opera)
        **bold text**; _italic text_
        """)
        source.importSourceName

    case (.operaGX, .bookmarks):
        NSLocalizedString("import.html.instructions.operagx.new", value: """
        %d Open **%s → Bookmarks → Bookmarks**
        %d Click **Import/Export… → Export Bookmarks** and save the file
        %d Upload the exported HTML file to DuckDuckGo
        """, comment: """
        Instructions to import Bookmarks exported as HTML from Opera GX browser.
        %N$d - step number
        %2$s - browser name (Opera GX)
        **bold text**; _italic text_
        """)
        source.importSourceName

    case (.yandex, .bookmarks):
        NSLocalizedString("import.html.instructions.yandex.new", value: """
        %d Open **%s → Favorites → Bookmark Manager**
        %d Click %@ **→ Export bookmarks to HTML file** and save the file
        %d Upload the exported HTML file to DuckDuckGo
        """, comment: """
        Instructions to import Bookmarks exported as HTML from Yandex Browser.
        %N$d - step number
        %2$s - browser name (Yandex)
        %4$@ - menu icon
        **bold text**; _italic text_
        """)
        source.importSourceName
        NSImage.menuVertical16

    case (.safari, .passwords), (.safariTechnologyPreview, .passwords):
        if #available(macOS 15.2, *) {
            NSLocalizedString("import.csv.instructions.safari.macos15-2", value: """
            %d Open **Safari → File → Export Browsing Data to File...**
            %d Select **Passwords** and save the file
            %d Double click the .zip file to unzip it, then upload the CSV file to DuckDuckGo
            """, comment: """
            Instructions to import Passwords as CSV from Safari zip file on >= macOS 15.2.
            %N$d - step number
            **bold text**; _italic text_
            """)
        } else {
            NSLocalizedString("import.csv.instructions.safari", value: """
            %d Open **Safari → File → Export → Passwords** and save the file
            %d Upload the exported CSV file to DuckDuckGo
            """, comment: """
            Instructions to import Passwords as CSV from Safari.
            %N$d - step number
            **bold text**; _italic text_
            """)
        }

    case (.safari, .bookmarks), (.safariTechnologyPreview, .bookmarks):
        NSLocalizedString("import.html.instructions.safari.new", value: """
        %d Open **Safari → File → Export → Bookmarks** and save the file
        %d Upload the exported HTML file to DuckDuckGo
        """, comment: """
        Instructions to import Bookmarks exported as HTML from Safari.
        %N$d - step number
        **bold text**; _italic text_
        """)

    case (.firefox, .passwords):
        NSLocalizedString("import.csv.instructions.firefox.new", value: """
        %d Open **%s →** %@ **→ Passwords →** %@ **→ Export Logins…** and save the file
        %d Upload the exported CSV file to DuckDuckGo
        """, comment: """
        Instructions to import Passwords as CSV from Firefox.
        %N$d - step number
        %2$s - browser name (Firefox)
        %3$@ - hamburger menu icon (first instance)
        %4$@ - horizontal menu icon (second instance)
        **bold text**; _italic text_
        """)
        source.importSourceName
        NSImage.menuHamburger16
        NSImage.menuHorizontal16

    case (.firefox, .bookmarks), (.tor, .bookmarks):
        NSLocalizedString("import.html.instructions.firefox.new", value: """
        %d Open **%s → Bookmarks → Manage Bookmarks**
        %d Click %@ **→ Export bookmarks to HTML…** and save the file
        %d Upload the exported HTML file to DuckDuckGo
        """, comment: """
        Instructions to import Bookmarks exported as HTML from Firefox based browsers.
        %N$d - step number
        %2$s - browser name (Firefox)
        %4$@ - import/export icon
        **bold text**; _italic text_
        """)
        source.importSourceName
        NSImage.importExport16

    case (.onePassword8, .passwords):
        NSLocalizedString("import.csv.instructions.onePassword8.new", value: """
        %d Open **%s → File → Export** and select an account to export
        %d Select format **CSV (Logins and Passwords only) → Export Data** and save the file
        %d Upload the exported CSV file to DuckDuckGo
        """, comment: """
        Instructions to import Passwords as CSV from 1Password 8.
        %N$d - step number
        %2$s - app name (1Password)
        **bold text**; _italic text_
        """)
        source.importSourceName

    case (.onePassword7, .passwords):
        NSLocalizedString("import.csv.instructions.onePassword7.new", value: """
        %d Open **%s** and select the vault to export **→ File → Export → All Items** from the menu bar
        %d Select the format **Comma Delimited Text (.csv)** and save the file
        %d Upload the exported CSV file to DuckDuckGo
        """, comment: """
        Instructions to import Passwords as CSV from 1Password 7.
        %N$d - step number
        %2$s - app name (1Password)
        **bold text**; _italic text_
        """)
        source.importSourceName

    case (.bitwarden, .passwords):
        NSLocalizedString("import.csv.instructions.bitwarden.new", value: """
        %d Open **%s → Settings** and scroll down to **Tools →** select **Export vault**
        %d Select the **File Format: .csv → Export vault** and save the file
        %d Upload the exported CSV file to DuckDuckGo
        """, comment: """
        Instructions to import Passwords as CSV from Bitwarden.
        %N$d - step number
        %2$s - app name (Bitwarden)
        **bold text**; _italic text_
        """)
        source.importSourceName

    case (.lastPass, .passwords):
        NSLocalizedString("import.csv.instructions.lastpass.new", value: """
        %d Log in to the **%s** website → select **Advanced Options → Export → Continue**. You'll receive a verification email.
        %d In the email, click **Continue export**, then return to **%s** and select **Advanced Options → Export → Submit** and save the **CSV** file
        %d Upload the exported CSV file to DuckDuckGo
        """, comment: """
        Instructions to import Passwords as CSV from LastPass.
        %N$d - step number
        %2$s - app name (LastPass) - first instance
        %4$s - app name (LastPass) - second instance
        **bold text**; _italic text_
        """)
        source.importSourceName
        source.importSourceName

    case (.csv, .passwords):
        BookmarksPasswordsTextProvider.passwordsText

    case (.bookmarksHTML, .bookmarks):
        BookmarksPasswordsTextProvider.bookmarksText

    case (.fileImport, .passwords):
        BookmarksPasswordsTextProvider.passwordsText

    case (.fileImport, .bookmarks):
        BookmarksPasswordsTextProvider.bookmarksText

    case (.bookmarksHTML, .passwords),
        (.tor, .passwords),
        (.onePassword7, .bookmarks),
        (.onePassword8, .bookmarks),
        (.bitwarden, .bookmarks),
        (.lastPass, .bookmarks),
        (.csv, .bookmarks),
        (_, .creditCards):
        assertionFailure("Invalid source/dataType")
    }
}

private struct BookmarksPasswordsTextProvider {
    static let bookmarksText: String = {
        NSLocalizedString("import.html.instructions.generic.new", value: """
        %d Open your old browser → **Bookmark Manager**
        %d **Export bookmarks to HTML…** and save the file
        %d Upload the exported HTML file to DuckDuckGo
        """, comment: """
        Instructions to import a generic HTML Bookmarks file.
        %N$d - step number
        **bold text**; _italic text_
        """)
    }()

    static let passwordsText: String = {
        NSLocalizedString("import.csv.instructions.generic.new", value: """
        The CSV importer will try to match column headers to their position.
        If there is no header, it supports two formats:
        %d URL, Username, Password
        %d Title, URL, Username, Password
        """, comment: """
        Instructions to import a generic CSV passwords file.
        %N$d - step number
        **bold text**; _italic text_
        """)
    }()
}

enum FilePickerMode {
    case fallback(dataType: DataImport.DataType)
    case archive
}

struct NewDataImportFilePickerScreenView: View {
    @Binding var model: DataImportViewModel
    let mode: FilePickerMode
    let dataTypes: Set<DataImport.DataType>
    let summaryTypes: Set<DataImport.DataType>

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            VStack(alignment: .center, spacing: 20) {
                if let importSourceImage = model.importSource.importSourceImage {
                    Image(nsImage: importSourceImage)
                        .resizable()
                        .frame(width: 72, height: 72)
                }

                titleText
                    .font(.title2.weight(.semibold))
                    .padding(.bottom, 20)
            }
        }
    }

    private var titleText: Text {
        switch mode {
        case .fallback(.creditCards):
            assert(false, "Credit card import fallback not handled yet")
            fallthrough
        case .fallback(.passwords):
            return Text(UserText.importPasswordsManuallyTitle)
        case .fallback(.bookmarks):
            return Text(UserText.importBookmarksManuallyTitle)
        case .archive:
            return Text("Import from \(model.importSource.importSourceName)")
        }
    }
}

struct NewFileImportView: View {
    enum Kind {
        case individual(dataType: DataImport.DataType)
        case archive

        func supportedFileTypes(for source: DataImport.Source) -> [UTType] {
            switch self {
            case .archive:
                return Array(source.archiveImportSupportedFiles)
            case .individual(dataType: let dataType):
                return dataType.allowedFileTypes
            }
        }
    }

    let source: DataImport.Source
    let allowedFileTypes: [UTType]
    let kind: Kind
    let action: () -> Void
    let onFileDrop: (URL) -> Void

    private var isButtonDisabled: Bool

    @State private var isTargeted: Bool = false

    init(source: DataImport.Source, allowedFileTypes: [UTType], isButtonDisabled: Bool, kind: Kind, action: (() -> Void)? = nil, onFileDrop: ((URL) -> Void)? = nil) {
        self.source = source
        self.allowedFileTypes = allowedFileTypes
        self.kind = kind
        self.action = action ?? {}
        self.onFileDrop = onFileDrop ?? { _ in }
        self.isButtonDisabled = isButtonDisabled
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            NewInstructionsView {
                switch kind {
                case .archive:
                    newFileImportMultipleTypeInstructionsBuilder(source: source)
                case .individual(let dataType):
                    newFileImportSingleTypeInstructionsBuilder(source: source, dataType: dataType)
                }
            }

            VStack(alignment: .center, spacing: 20) {
                Image(nsImage: isTargeted ? DesignSystemImages.Color.Size128.fileDrop : DesignSystemImages.Color.Size128.fileDrag)

                VStack(alignment: .center, spacing: 0) {
                    Text(UserText.importDragAndDropFile).font(.system(size: 14, weight: .bold))
                    button(UserText.importDataSelectFileButtonTitle)
                        .padding(.top, 10)
                }
                .alignmentGuide(.lastTextBaseline) { d in d[.lastTextBaseline] }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .center)
            .background(fileDropBackgroundColor)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .inset(by: 0.5)
                    .stroke(fileDropStrokeColor, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
            )
            .onDrop(of: allowedFileTypes, isTargeted: $isTargeted, perform: onDrop)
        }
    }

    private var fileDropStrokeColor: Color {
        isTargeted ? Color(designSystemColor: .accentPrimary) : Color(designSystemColor: .controlsFillTertiary)
    }

    private var fileDropBackgroundColor: Color {
        isTargeted ? Color(designSystemColor: .accentPrimary).opacity(0.2) : Color(designSystemColor: .surfaceSecondary)
    }

    private func button(_ title: String) -> AnyView {
        AnyView(
            Button(title, action: action)
                .disabled(isButtonDisabled)
        )
    }

    private func onDrop(_ providers: [NSItemProvider], _ location: CGPoint) -> Bool {
        let allowedTypeIdentifiers = providers.reduce(into: Set<String>()) {
            $0.formUnion($1.registeredTypeIdentifiers)
        }.intersection(allowedFileTypes.map(\.identifier))

        guard let typeIdentifier = allowedTypeIdentifiers.first,
              let provider = providers.first(where: {
                  $0.hasItemConformingToTypeIdentifier(typeIdentifier)
              }) else {
            Logger.dataImportExport.error("invalid type identifiers: \(allowedTypeIdentifiers)")
            return false
        }

        provider.loadItem(forTypeIdentifier: typeIdentifier) { data, error in
            guard let data else {
                Logger.dataImportExport.error("error loading \(typeIdentifier): \(error?.localizedDescription ?? "?")")
                return
            }
            let url: URL
            switch data {
            case let value as URL:
                url = value
            case let data as Data:
                guard let value = URL(dataRepresentation: data, relativeTo: nil) else {
                    Logger.dataImportExport.error("could not decode data: \(data.debugDescription)")
                    return
                }
                url = value
            default:
                Logger.dataImportExport.error("unsupported data: \(String(describing: data))")
                return
            }

            onFileDrop(url)
        }

        return true
    }
}

struct NewInstructionsView: View {

    // item used in InstructionBuilder: string literal, NSImage or Choose File Button (AnyView)
    enum InstructionsItem {
        case string(String)
        case image(NSImage)
        case view(AnyView)
    }
    // Text item view ViewModel - joined in a line using Text(string).bold().italic() + Text(image).. seq
    enum TextItem {
        case image(NSImage)
        case text(text: String, isBold: Bool, isItalic: Bool)
    }
    // Possible NewInstructionsView line components:
    // - lineNumber (number in a circle)
    // - textItems: Text(string).bold().italic() + Text(image).. seq
    // - view: Choose File Button
    enum NewInstructionsViewItem {
        case lineNumber(Int)
        case textItems([TextItem])
        case view(AnyView)
    }

    // View Model
    private let instructions: [[NewInstructionsViewItem]]

    init(@InstructionsBuilder builder: () -> [InstructionsItem]) {
        var args = builder()

        guard case .string(let format) = args.first else {
            assertionFailure("First item should provide instructions format using NSLocalizedString")
            self.instructions = []
            return
        }

        do {
            // parse %12$d, %23$s, %34$@ out of the localized format into component sequence
            let formatLines = try InstructionsFormatParser().parse(format: format)

            // assertion helper
            func fline(_ lineIdx: Int) -> String {
                format.components(separatedBy: "\n")[safe: lineIdx] ?? "?"
            }

            // arguments are positioned (%42$s %23$@) but lines numbers are auto-incremented
            // but the line arguments (%12$d) are still indexed.
            // insert fake components at .line components positions to keep order
            let lineNumberArgumentIndices = formatLines.reduce(into: IndexSet()) {
                $0.formUnion($1.reduce(into: IndexSet()) {
                    if case .number(argIndex: let argIndex) = $1 {
                        $0.insert(argIndex)
                    }
                })
            }
            for idx in lineNumberArgumentIndices {
                args.insert(.string(""), at: idx)
            }

            // generate instructions view model from localized format
            var result = [[NewInstructionsViewItem]]()
            var lineNumber = 1
            var usedArgs = IndexSet()
            for (lineIdx, line) in formatLines.enumerated() {
                // collect view items placed in line
                var resultLine = [NewInstructionsViewItem]()
                func appendTextItem(_ textItem: TextItem) {
                    // text item should be appended to an ongoing textItem sequence if present
                    if case .textItems(var items) = resultLine.last {
                        items.append(textItem)
                        resultLine[resultLine.endIndex - 1] = .textItems(items)
                    } else {
                        // previous item is not .textItems - initiate a new textItem sequence
                        resultLine.append(.textItems([textItem]))
                    }
                }

                for component in line {
                    switch component {
                    // %d line number argument
                    case .number(let argIndex):
                        resultLine.append(.lineNumber(lineNumber))
                        usedArgs.insert(argIndex)
                        lineNumber += 1 // line number is auto-incremented

                    // text literal [optionally with markdown attributes]
                    case .text(let text, bold: let bold, italic: let italic):
                        appendTextItem(.text(text: text, isBold: bold, isItalic: italic))

                    // %s string argument
                    case .string(let argIndex, bold: let bold, italic: let italic):
                        switch args[safe: argIndex] {
                        case .string(let str):
                            appendTextItem(.text(text: str, isBold: bold, isItalic: italic))
                        case .none:
                            assertionFailure("String argument missing at index \(argIndex) in line \(lineIdx + 1):\n“\(fline(lineIdx))”.\nArgs:\n\(args)")
                        case .image(let obj as Any), .view(let obj as Any):
                            assertionFailure("Unexpected object argument at index \(argIndex):\n\(obj)\nExpected object in line \(lineIdx + 1):\n“\(fline(lineIdx))”.\nArgs:\n\(args)")
                        }
                        usedArgs.insert(argIndex)

                    // %@ object argument - inline image or button (view)
                    case .object(let argIndex):
                        switch args[safe: argIndex] {
                        case .image(let image):
                            appendTextItem(.image(image))
                        case .view(let view):
                            resultLine.append(.view(view))
                        case .none:
                            assertionFailure("Object argument missing at index \(argIndex) in line \(lineIdx + 1):\n“\(fline(lineIdx))”.\nArgs:\n\(args)")
                        case .string(let string):
                            assertionFailure("Unexpected string argument at index \(argIndex):\n“\(string)”.\nExpected object in line \(lineIdx + 1):\n“\(fline(lineIdx))”.\nArgs:\n\(args)")
                        }

                        usedArgs.insert(argIndex)
                    }
                }
                result.append(resultLine)
            }
            assert(usedArgs.subtracting(IndexSet(args.indices)).isEmpty,
                   "Unused arguments at indices \(usedArgs.subtracting(IndexSet(args.indices)))")
            self.instructions = result

        } catch {
            assertionFailure("Could not build instructions view: \(error)")
            self.instructions = []
        }
    }

    @resultBuilder
    struct InstructionsBuilder {
        static func buildBlock(_ components: [InstructionsItem]...) -> [InstructionsItem] {
            return components.flatMap { $0 }
        }

        static func buildOptional(_ components: [InstructionsItem]?) -> [InstructionsItem] {
            return components ?? []
        }

        static func buildEither(first component: [InstructionsItem]) -> [InstructionsItem] {
            component
        }

        static func buildEither(second component: [InstructionsItem]) -> [InstructionsItem] {
            component
        }

        static func buildLimitedAvailability(_ component: [InstructionsItem]) -> [InstructionsItem] {
            component
        }

        static func buildArray(_ components: [[InstructionsItem]]) -> [InstructionsItem] {
            components.flatMap { $0 }
        }

        static func buildExpression(_ expression: [InstructionsItem]) -> [InstructionsItem] {
            return expression
        }

        static func buildExpression(_ value: String) -> [InstructionsItem] {
            return [.string(value)]
        }

        static func buildExpression(_ value: NSImage) -> [InstructionsItem] {
            return [.image(value)]
        }

        static func buildExpression(_ value: some View) -> [InstructionsItem] {
            return [.view(AnyView(value))]
        }

        static func buildExpression(_ expression: Void) -> [InstructionsItem] {
            return []
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(instructions.indices, id: \.self) { i in
                HStack(alignment: .center, spacing: 8) {
                    ForEach(instructions[i].indices, id: \.self) { j in
                        switch instructions[i][j] {
                        case .lineNumber(let number):
                            NewCircleNumberView(number: number)
                        case .textItems(let textParts):
                            Text(textParts)
                                .makeSelectable()
                                .frame(minHeight: NewCircleNumberView.Constants.diameter)
                        case .view(let view):
                            view
                        }
                    }
                }
            }
        }
    }

}

private extension Text {

    init(_ textPart: NewInstructionsView.TextItem) {
        switch textPart {
        case .image(let image):
            self.init(Image(nsImage: image))
            self = self
                .baselineOffset(-3)

        case .text(let text, let isBold, let isItalic):
            self.init(text)
            if isBold {
                self = self.bold()
            }
            if isItalic {
                self = self.italic()
            }
        }
    }

    init(_ textParts: [NewInstructionsView.TextItem]) {
        guard !textParts.isEmpty else {
            assertionFailure("Empty TextParts")
            self.init("")
            return
        }
        self.init(textParts[0])

        guard textParts.count > 1 else { return }
        for textPart in textParts[1...] {
            // swiftlint:disable:next shorthand_operator
            self = self + Text(textPart)
        }
    }

}

struct NewCircleNumberView: View {

    enum Constants {
        static let diameter: CGFloat = 20
    }

    let number: Int

    var body: some View {
        Circle()
            .fill(.globalBackground)
            .frame(width: Constants.diameter, height: Constants.diameter)
            .overlay(
                Text("\(number)")
                    .foregroundColor(Color(.onboardingActionButton))
                    .bold()

            )
    }

}

// MARK: - Preview

#Preview("Multiple Types") {
    VStack(spacing: 20) {
        Text("Safari Multi-Type Import").font(.headline)
        NewInstructionsView {
            newFileImportMultipleTypeInstructionsBuilder(source: .safari)
        }
    }
    .padding()
    .frame(width: 600)
    .font(.system(size: 13))
}

#Preview("Passwords") {
    ScrollView {
        VStack(alignment: .leading, spacing: 30) {
            Text("Chrome").font(.headline)
            NewInstructionsView {
                newFileImportSingleTypeInstructionsBuilder(source: .chrome, dataType: .passwords)
            }

            Divider()

            Text("Brave").font(.headline)
            NewInstructionsView {
                newFileImportSingleTypeInstructionsBuilder(source: .brave, dataType: .passwords)
            }

            Divider()

            Text("Chromium").font(.headline)
            NewInstructionsView {
                newFileImportSingleTypeInstructionsBuilder(source: .chromium, dataType: .passwords)
            }

            Divider()

            Text("Edge").font(.headline)
            NewInstructionsView {
                newFileImportSingleTypeInstructionsBuilder(source: .edge, dataType: .passwords)
            }

            Divider()

            Text("Cốc Cốc").font(.headline)
            NewInstructionsView {
                newFileImportSingleTypeInstructionsBuilder(source: .coccoc, dataType: .passwords)
            }

            Divider()

            Text("Opera").font(.headline)
            NewInstructionsView {
                newFileImportSingleTypeInstructionsBuilder(source: .opera, dataType: .passwords)
            }

            Divider()

            Text("Vivaldi").font(.headline)
            NewInstructionsView {
                newFileImportSingleTypeInstructionsBuilder(source: .vivaldi, dataType: .passwords)
            }

            Divider()

            Text("Opera GX").font(.headline)
            NewInstructionsView {
                newFileImportSingleTypeInstructionsBuilder(source: .operaGX, dataType: .passwords)
            }

            Divider()

            Text("Yandex").font(.headline)
            NewInstructionsView {
                newFileImportSingleTypeInstructionsBuilder(source: .yandex, dataType: .passwords)
            }

            Divider()

            Text("Safari").font(.headline)
            NewInstructionsView {
                newFileImportSingleTypeInstructionsBuilder(source: .safari, dataType: .passwords)
            }

            Divider()

            Text("Firefox").font(.headline)
            NewInstructionsView {
                newFileImportSingleTypeInstructionsBuilder(source: .firefox, dataType: .passwords)
            }

            Divider()

            Text("1Password 8").font(.headline)
            NewInstructionsView {
                newFileImportSingleTypeInstructionsBuilder(source: .onePassword8, dataType: .passwords)
            }

            Divider()

            Text("1Password 7").font(.headline)
            NewInstructionsView {
                newFileImportSingleTypeInstructionsBuilder(source: .onePassword7, dataType: .passwords)
            }

            Divider()

            Text("Bitwarden").font(.headline)
            NewInstructionsView {
                newFileImportSingleTypeInstructionsBuilder(source: .bitwarden, dataType: .passwords)
            }

            Divider()

            Text("LastPass").font(.headline)
            NewInstructionsView {
                newFileImportSingleTypeInstructionsBuilder(source: .lastPass, dataType: .passwords)
            }

            Divider()

            Text("Generic CSV").font(.headline)
            NewInstructionsView {
                newFileImportSingleTypeInstructionsBuilder(source: .csv, dataType: .passwords)
            }
        }
        .padding()
    }
    .frame(width: 600, height: 800)
    .font(.system(size: 13))
}

#Preview("Bookmarks") {
    ScrollView {
        VStack(alignment: .leading, spacing: 30) {
            Text("Chrome").font(.headline)
            NewInstructionsView {
                newFileImportSingleTypeInstructionsBuilder(source: .chrome, dataType: .bookmarks)
            }

            Divider()

            Text("Brave").font(.headline)
            NewInstructionsView {
                newFileImportSingleTypeInstructionsBuilder(source: .brave, dataType: .bookmarks)
            }

            Divider()

            Text("Chromium").font(.headline)
            NewInstructionsView {
                newFileImportSingleTypeInstructionsBuilder(source: .chromium, dataType: .bookmarks)
            }

            Divider()

            Text("Edge").font(.headline)
            NewInstructionsView {
                newFileImportSingleTypeInstructionsBuilder(source: .edge, dataType: .bookmarks)
            }

            Divider()

            Text("Cốc Cốc").font(.headline)
            NewInstructionsView {
                newFileImportSingleTypeInstructionsBuilder(source: .coccoc, dataType: .bookmarks)
            }

            Divider()

            Text("Vivaldi").font(.headline)
            NewInstructionsView {
                newFileImportSingleTypeInstructionsBuilder(source: .vivaldi, dataType: .bookmarks)
            }

            Divider()

            Text("Opera").font(.headline)
            NewInstructionsView {
                newFileImportSingleTypeInstructionsBuilder(source: .opera, dataType: .bookmarks)
            }

            Divider()

            Text("Opera GX").font(.headline)
            NewInstructionsView {
                newFileImportSingleTypeInstructionsBuilder(source: .operaGX, dataType: .bookmarks)
            }

            Divider()

            Text("Yandex").font(.headline)
            NewInstructionsView {
                newFileImportSingleTypeInstructionsBuilder(source: .yandex, dataType: .bookmarks)
            }

            Divider()

            Text("Safari").font(.headline)
            NewInstructionsView {
                newFileImportSingleTypeInstructionsBuilder(source: .safari, dataType: .bookmarks)
            }

            Divider()

            Text("Firefox").font(.headline)
            NewInstructionsView {
                newFileImportSingleTypeInstructionsBuilder(source: .firefox, dataType: .bookmarks)
            }

            Divider()

            Text("Tor").font(.headline)
            NewInstructionsView {
                newFileImportSingleTypeInstructionsBuilder(source: .tor, dataType: .bookmarks)
            }

            Divider()

            Text("Generic HTML").font(.headline)
            NewInstructionsView {
                newFileImportSingleTypeInstructionsBuilder(source: .bookmarksHTML, dataType: .bookmarks)
            }
        }
        .padding()
    }
    .frame(width: 600, height: 800)
    .font(.system(size: 13))
}
