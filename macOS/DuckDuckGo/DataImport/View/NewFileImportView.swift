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

@NewInstructionsView.InstructionsBuilder
func newFileImportMultipleTypeInstructionsBuilder(source: DataImport.Source) -> [NewInstructionsView.InstructionsItem] {
    switch source {
    case .safari, .safariTechnologyPreview:
        NSLocalizedString("import.zip.instructions.safari", value: """
        %d Open %@ **Safari → File → Export Browsing Data to File...**
        %d Choose **Bookmarks, Passwords,** and/or **Credit Cards**, then click **Export**
        %d Add the exported ZIP file below
        """, comment: """
        Instructions to import multiple data types exported as ZIP from Safari.
        %N$d - step number
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
         .csv, .bookmarksHTML:
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
        %4$@ - hamburger menu icon
        %8$@ - “Select Passwords CSV File” button
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
        %4$@, %6$@ - hamburger menu icon
        %10$@ - “Select Passwords CSV File” button
        **bold text**; _italic text_
        """)
        source.importSourceName
        NSImage.menuHamburger16
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
        %4$@ - hamburger menu icon
        %8$@ - “Select Passwords CSV File” button
        **bold text**; _italic text_
        """)
        source.importSourceName
        NSImage.menuVertical16

    case (.coccoc, .passwords):
        NSLocalizedString("import.csv.instructions.coccoc.new", value: """
        %d Open **%s**
        %d Type “_coccoc://settings/passwords_” into the Address bar
        %d Click %@ (on the right from _Saved Passwords_) and select **Export passwords**
        %d Save the passwords file someplace you can find it (e.g., Desktop)
        """, comment: """
        Instructions to import Passwords as CSV from Cốc Cốc browser.
        %N$d - step number
        %2$s - browser name (Cốc Cốc)
        %5$@ - hamburger menu icon
        %8$@ - “Select Passwords CSV File” button
        **bold text**; _italic text_
        """)
        source.importSourceName
        NSImage.menuVertical16

    case (.opera, .passwords):
        NSLocalizedString("import.csv.instructions.opera.new", value: """
        %d Open **%s** → **View → Show Password Manager → Settings**
        %d Find “Export Passwords” → click **Download File** and save the file
        %d Upload the exported CSV file to DuckDuckGo
        """, comment: """
        Instructions to import Passwords as CSV from Opera browser.
        %N$d - step number
        %2$s - browser name (Opera)
        %8$@ - “Select Passwords CSV File” button
        **bold text**; _italic text_
        """)
        source.importSourceName

    case (.vivaldi, .passwords):
        NSLocalizedString("import.csv.instructions.vivaldi.new", value: """
        %d Open **%s**
        %d Type “_chrome://settings/passwords_” into the Address bar
        %d Click %@ (on the right from _Saved Passwords_) and select **Export passwords**
        %d Save the file someplace you can find it (e.g., Desktop)
        %d %@
        """, comment: """
        Instructions to import Passwords exported as CSV from Vivaldi browser.
        %N$d - step number
        %2$s - browser name (Vivaldi)
        %5$@ - menu button icon
        %8$@ - “Select Passwords CSV File” button
        **bold text**; _italic text_
        """)
        source.importSourceName
        NSImage.menuVertical16

    case (.operaGX, .passwords):
        NSLocalizedString("import.csv.instructions.operagx.new", value: """
        %d Open **%s** → **View → Show Password Manager → Settings**
        %d Click %@ (on the right from _Saved Passwords_) → select **Export passwords** and save the file
        %d Upload the exported CSV file to DuckDuckGo
        """, comment: """
        Instructions to import Passwords as CSV from Opera GX browsers.
        %N$d - step number
        %2$s - browser name (Opera GX)
        %5$@ - menu button icon
        %8$@ - “Select Passwords CSV File” button
        **bold text**; _italic text_
        """)
        source.importSourceName
        NSImage.menuVertical16

    case (.yandex, .passwords):
        NSLocalizedString("import.csv.instructions.yandex.new", value: """
        %d Open **%s** → %@ → **Passwords and cards**
        %d Click %@ then **Export passwords**
        %d Choose **To a text file (not secure)** and click **Export**
        %d Save the passwords file someplace you can find it (e.g., Desktop)
        """, comment: """
        Instructions to import Passwords as CSV from Yandex Browser.
        %N$d - step number
        %2$s - browser name (Yandex)
        %4$@ - hamburger menu icon
        %8$@ - “Select Passwords CSV File” button
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
        %d Open **%s** → **Bookmarks → Bookmark Manager**
        %d Click %@ → **Export Bookmarks** and save the file
        %d Upload the exported HTML file to DuckDuckGo
        """, comment: """
        Instructions to import Bookmarks exported as HTML from Chromium-based browsers.
        %N$d - step number
        %2$s - browser name
        %5$@ - hamburger menu icon
        %8$@ - “Select Bookmarks HTML File” button
        **bold text**; _italic text_
        """)
        source.importSourceName
        NSImage.menuVertical16

    case (.vivaldi, .bookmarks):
        NSLocalizedString("import.html.instructions.vivaldi.new", value: """
        %d Open **%s**
        %d Use the Menu Bar to select **File → Export Bookmarks…**
        %d Save the file someplace you can find it (e.g., Desktop)
        """, comment: """
        Instructions to import Bookmarks exported as HTML from Vivaldi browser.
        %N$d - step number
        %2$s - browser name (Vivaldi)
        %6$@ - “Select Bookmarks HTML File” button
        **bold text**; _italic text_
        """)
        source.importSourceName

    case (.opera, .bookmarks):
        NSLocalizedString("import.html.instructions.opera.new", value: """
        %d Open **%s**
        %d Use the Menu Bar to select **Bookmarks → Bookmarks**
        %d Click **Open full Bookmarks view…** in the bottom left
        %d Click **Import/Export…** in the bottom left and select **Export Bookmarks**
        %d Save the file someplace you can find it (e.g., Desktop)
        """, comment: """
        Instructions to import Bookmarks exported as HTML from Opera browser.
        %N$d - step number
        %2$s - browser name (Opera)
        %8$@ - “Select Bookmarks HTML File” button
        **bold text**; _italic text_
        """)
        source.importSourceName

    case (.operaGX, .bookmarks):
        NSLocalizedString("import.html.instructions.operagx.new", value: """
        %d Open **%s**
        %d Use the Menu Bar to select **Bookmarks → Bookmarks**
        %d Click **Import/Export…** in the bottom left and select **Export Bookmarks**
        %d Save the file someplace you can find it (e.g., Desktop)
        """, comment: """
        Instructions to import Bookmarks exported as HTML from Opera GX browser.
        %N$d - step number
        %2$s - browser name (Opera GX)
        %7$@ - “Select Bookmarks HTML File” button
        **bold text**; _italic text_
        """)
        source.importSourceName

    case (.yandex, .bookmarks):
        NSLocalizedString("import.html.instructions.yandex.new", value: """
        %d Open **%s**
        %d Use the Menu Bar to select **Favorites → Bookmark Manager**
        %d Click %@ then **Export bookmarks to HTML file**
        %d Save the file someplace you can find it (e.g., Desktop)
        """, comment: """
        Instructions to import Bookmarks exported as HTML from Yandex Browser.
        %N$d - step number
        %2$s - browser name (Yandex)
        %5$@ - hamburger menu icon
        %8$@ - “Select Bookmarks HTML File” button
        **bold text**; _italic text_
        """)
        source.importSourceName
        NSImage.menuVertical16

    case (.safari, .passwords), (.safariTechnologyPreview, .passwords):
        if #available(macOS 15.2, *) {
            NSLocalizedString("import.csv.instructions.safari.macos15-2", value: """
            %d Open **Safari**
            %d Open the **File menu → Export Browsing Data to File...**
            %d Select **passwords** and save the file someplace you can find it (e.g., Desktop)
            %d Double click the .zip file to unzip it
            """, comment: """
            Instructions to import Passwords as CSV from Safari zip file on >= macOS 15.2.
            %N$d - step number
            %5$@ - “Select Passwords CSV File” button
            **bold text**; _italic text_
            """)
        } else {
            NSLocalizedString("import.csv.instructions.safari", value: """
            %d Open **Safari**
            %d Select **File → Export → Passwords**
            %d Save the passwords file someplace you can find it (e.g., Desktop)
            """, comment: """
            Instructions to import Passwords as CSV from Safari.
            %N$d - step number
            %5$@ - “Select Passwords CSV File” button
            **bold text**; _italic text_
            """)
        }

    case (.safari, .bookmarks), (.safariTechnologyPreview, .bookmarks):
        NSLocalizedString("import.html.instructions.safari.new", value: """
        %d Open **Safari**
        %d Select **File → Export → Bookmarks**
        %d Save the passwords file someplace you can find it (e.g., Desktop)
        """, comment: """
        Instructions to import Bookmarks exported as HTML from Safari.
        %N$d - step number
        %5$@ - “Select Bookmarks HTML File” button
        **bold text**; _italic text_
        """)

    case (.firefox, .passwords):
        NSLocalizedString("import.csv.instructions.firefox.new", value: """
        %d Open **%s** → %@ → **Passwords** → %@ → **Export Logins…** and save the file
        %d Upload the exported CSV file to DuckDuckGo
        """, comment: """
        Instructions to import Passwords as CSV from Firefox.
        %N$d - step number
        %2$s - browser name (Firefox)
        %4$@, %6$@ - hamburger menu icon
        %9$@ - “Select Passwords CSV File” button
        **bold text**; _italic text_
        """)
        source.importSourceName
        NSImage.menuHamburger16
        NSImage.menuHorizontal16

    case (.firefox, .bookmarks), (.tor, .bookmarks):
        NSLocalizedString("import.html.instructions.firefox.new", value: """
        %d Open **%s**
        %d Use the Menu Bar to select **Bookmarks → Manage Bookmarks**
        %d Click %@ then **Export bookmarks to HTML…**
        %d Save the file someplace you can find it (e.g., Desktop)
        """, comment: """
        Instructions to import Bookmarks exported as HTML from Firefox based browsers.
        %N$d - step number
        %2$s - browser name (Firefox)
        %5$@ - hamburger menu icon
        %8$@ - “Select Bookmarks HTML File” button
        **bold text**; _italic text_
        """)
        source.importSourceName
        NSImage.importExport16

    case (.onePassword8, .passwords):
        NSLocalizedString("import.csv.instructions.onePassword8.new", value: """
        %d Open and unlock **%s**
        %d Select **File → Export** from the Menu Bar and choose the account you want to export
        %d Enter your 1Password account password
        %d Select the File Format: **CSV (Logins and Passwords only)**
        %d Click Export Data and save the file someplace you can find it (e.g., Desktop)
        """, comment: """
        Instructions to import Passwords as CSV from 1Password 8.
        %2$s - app name (1Password)
        %8$@ - “Select 1Password CSV File” button
        **bold text**; _italic text_
        """)
        source.importSourceName

    case (.onePassword7, .passwords):
        NSLocalizedString("import.csv.instructions.onePassword7.new", value: """
        %d Open and unlock **%s**
        %d Select the vault you want to export (you can only export one vault at a time)
        %d Select **File → Export → All Items** from the Menu Bar
        %d Enter your 1Password main or account password
        %d Select the File Format: **iCloud Keychain (.csv)**
        %d Save the passwords file someplace you can find it (e.g., Desktop)
        """, comment: """
        Instructions to import Passwords as CSV from 1Password 7.
        %2$s - app name (1Password)
        %9$@ - “Select 1Password CSV File” button
        **bold text**; _italic text_
        """)
        source.importSourceName

    case (.bitwarden, .passwords):
        NSLocalizedString("import.csv.instructions.bitwarden.new", value: """
        %d Open and unlock **%s**
        %d Select **File → Export vault** from the Menu Bar
        %d Select the File Format: **.csv**
        %d Enter your Bitwarden main password
        %d Click %@ and save the file someplace you can find it (e.g., Desktop)
        """, comment: """
        Instructions to import Passwords as CSV from Bitwarden.
        %2$s - app name (Bitwarden)
        %7$@ - hamburger menu icon
        %9$@ - “Select Bitwarden CSV File” button
        **bold text**; _italic text_
        """)
        source.importSourceName
        NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: nil) ?? .downloads

    case (.lastPass, .passwords):
        NSLocalizedString("import.csv.instructions.lastpass.new", value: """
        %d Click on the **%s** icon in your browser and enter your main password
        %d Select **Open My Vault**
        %d From the sidebar select **Advanced Options → Export**
        %d Enter your LastPass main password
        %d Select the File Format: **Comma Delimited Text (.csv)**
        """, comment: """
        Instructions to import Passwords as CSV from LastPass.
        %2$s - app name (LastPass)
        %8$@ - “Select LastPass CSV File” button
        **bold text**; _italic text_
        """)
        source.importSourceName

    case (.csv, .passwords):
        NSLocalizedString("import.csv.instructions.generic.new", value: """
        The CSV importer will try to match column headers to their position.
        If there is no header, it supports two formats:
        %d URL, Username, Password
        %d Title, URL, Username, Password
        """, comment: """
        Instructions to import a generic CSV passwords file.
        %N$d - step number
        %3$@ - “Select Passwords CSV File” button
        **bold text**; _italic text_
        """)

    case (.bookmarksHTML, .bookmarks):
        NSLocalizedString("import.html.instructions.generic.new", value: """
        %d Open your old browser
        %d Open **Bookmark Manager**
        %d Export bookmarks to HTML…
        %d Save the file someplace you can find it (e.g., Desktop)
        """, comment: """
        Instructions to import a generic HTML Bookmarks file.
        %N$d - step number
        %6$@ - “Select Bookmarks HTML File” button
        **bold text**; _italic text_
        """)

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

enum FilePickerMode {
    case fallback(dataType: DataImport.DataType)
    case archive
}

struct NewDataImportFilePickerScreenView: View {
    @Binding var model: DataImportViewModel
    let mode: FilePickerMode
    let dataTypes: Set<DataImport.DataType>
    let summaryTypes: Set<DataImport.DataType>
    let dismiss: () -> Void

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
                Image(.passwordsAdd96)
                    .resizable()
                    .frame(width: 54, height: 54)
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

#Preview {
    HStack {
        NewFileImportView(source: .onePassword8, allowedFileTypes: [.zip], isButtonDisabled: false, kind: .archive)
            .padding()
            .frame(width: 512 - 20)
    }
    .font(.system(size: 13))
    .background(Color.white)
}
