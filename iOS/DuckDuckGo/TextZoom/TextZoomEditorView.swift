//
//  TextZoomEditorView.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import DesignResourcesKitIcons
import UIComponents

struct TextZoomEditorView: View {

    @ObservedObject var model: TextZoomEditorModel

    @Environment(\.dismiss) var dismiss

    private var closeButton: some View {
        Button {
            model.onDismiss()
            dismiss()
        } label: {
            Image(uiImage: DesignSystemImages.Glyphs.Size24.close)
        }
        .buttonStyle(CloseButtonStyle())
        .accessibilityLabel(UserText.keyCommandClose)
    }

    @ViewBuilder
    func header() -> some View {
        ZStack(alignment: .center) {
            Text(model.title)
                .font(Font(uiFont: .daxHeadline()))
                .frame(alignment: .center)
                .foregroundStyle(Color(designSystemColor: .textPrimary))
                // centers properly but also padds the sides in case a translation makes this overlap the close button
                .padding(.horizontal, CloseButtonStyle.Constant.padding + 24)

            HStack {
                Spacer()
                closeButton
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
    }

    func slider() -> some View {
        HStack(spacing: 6) {
            Button {
                model.decrement()
            } label: {
                Image(uiImage: DesignSystemImages.Glyphs.Size24.fontSmaller)
            }
            .foregroundColor(Color(designSystemColor: .textPrimary))
            .padding(12)
            .padding(.leading, 8)

            IntervalSliderRepresentable(
                value: $model.value,
                steps: TextZoomLevel.allCases.map { $0.rawValue })
            .padding(.vertical)

            Button {
                model.increment()
            } label: {
                Image(uiImage: DesignSystemImages.Glyphs.Size24.fontLarger)
            }
            .foregroundColor(Color(designSystemColor: .textPrimary))
            .padding(12)
            .padding(.trailing, 8)
        }
        .background(RoundedRectangle(cornerRadius: 8)
            .foregroundColor(Color(designSystemColor: .surface)))
        .frame(height: 64)
        .padding(.horizontal, 16)

    }

    var body: some View {
        VStack {
            header()
            Spacer()
            slider()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(designSystemColor: .background))
    }

}
