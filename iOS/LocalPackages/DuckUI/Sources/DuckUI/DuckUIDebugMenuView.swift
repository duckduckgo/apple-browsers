//
//  DuckUIDebugMenuView.swift
//  DuckDuckGo
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
import DesignResourcesKit

/// A runtime catalog of the DuckUI component galleries, surfaced in the app's internal
/// debug menu.
public struct DuckUIDebugMenuView: View {

    public init() {}

    public var body: some View {
        List {
            Section(header: Text(verbatim: "Buttons")) {
                row("Button Styles (Legacy)", title: "Buttons (Legacy)") {
                    ButtonStylesGallery(isRebranded: false)
                }
                row("Button Styles (Rebranded)", title: "Buttons (Rebranded)") {
                    ButtonStylesGallery(isRebranded: true)
                }
                row("iOS Buttons (Figma)", title: "iOS Buttons (Figma)") {
                    IOSButtonsDebugView()
                }
            }
            .listRowBackground(Color(designSystemColor: .surface))

            Section(header: Text(verbatim: "Typography")) {
                row("Text Styles", title: "Text Styles") {
                    TextStylesGallery()
                }
                row("Fonts", title: "Fonts") {
                    AppFontGallery()
                }
            }
            .listRowBackground(Color(designSystemColor: .surface))
        }
        .navigationTitle("DuckUI")
    }

    private func row<Content: View>(
        _ label: String,
        title: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        NavigationLink(destination: LazyView(DuckUIPreviewContainer(title: title, content: content))) {
            Text(verbatim: label)
        }
    }
}

/// Wraps a gallery with a System / Light / Dark appearance picker so both colour-scheme
/// variants are reachable at runtime.
private struct DuckUIPreviewContainer<Content: View>: View {

    enum Appearance: String, CaseIterable, Identifiable {
        case light = "Light"
        case dark = "Dark"

        var id: String { rawValue }

        var colorScheme: ColorScheme {
            switch self {
            case .light: return .light
            case .dark: return .dark
            }
        }
    }

    let title: String
    @ViewBuilder let content: () -> Content
    @State private var appearance: Appearance = .light

    var body: some View {
        VStack(spacing: 0) {
            Picker("Appearance", selection: $appearance) {
                ForEach(Appearance.allCases) { option in
                    Text(verbatim: option.rawValue).tag(option)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(16)

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .environment(\.colorScheme, appearance.colorScheme)
        .preferredColorScheme(appearance.colorScheme)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Defers building `Content` until the view is actually rendered, so navigation
/// destinations are not constructed eagerly when the list appears.
private struct LazyView<Content: View>: View {
    let build: () -> Content

    init(_ build: @autoclosure @escaping () -> Content) {
        self.build = build
    }

    var body: Content {
        build()
    }
}
