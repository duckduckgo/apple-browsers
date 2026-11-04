//
//  AddFavoriteView.swift
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
import SwiftUI

struct AddFavoriteView: View {
    @ObservedObject var model: AddFavoriteViewModel
    let onClose: () -> Void
    @State private var saveFailed = false
    @FocusState private var isURLFocused: Bool

    var body: some View {
        ScrollView(showsIndicators: false) {
            form
        }
        .onAppear { isURLFocused = true }
        .alert(UserText.newTabPageFavoriteSaveFailed, isPresented: $saveFailed) {
            Button(UserText.actionOK, role: .cancel) { }
        }
    }

    var form: some View {
        VStack(spacing: Metrics.headerToFormSpacing) {
            header
            VStack(spacing: 0) {
                TextField(UserText.newTabPageFavoriteName, text: $model.name,
                          prompt: Text(UserText.newTabPageFavoriteName).foregroundColor(Color(designSystemColor: .textSecondary)))
                    .padding(.horizontal, Metrics.contentPadding)
                    .padding(.vertical, Metrics.fieldVerticalPadding)
                Color(designSystemColor: .decorationPrimary)
                    .frame(height: Metrics.dividerHeight)
                    .padding(.leading, Metrics.contentPadding)
                    .accessibilityHidden(true)
                TextField(UserText.newTabPageFavoriteURL, text: $model.urlText,
                          prompt: Text(UserText.newTabPageFavoriteURL).foregroundColor(Color(designSystemColor: .textSecondary)))
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .focused($isURLFocused)
                    .padding(.horizontal, Metrics.contentPadding)
                    .padding(.vertical, Metrics.fieldVerticalPadding)
                    .onSubmit(save)
            }
            .daxBodyRegular()
            .foregroundColor(Color(designSystemColor: .textPrimary))
            .background(Color(designSystemColor: .controlsFillPrimary))
            .clipShape(RoundedRectangle(cornerRadius: Metrics.formCornerRadius))
            .padding(.horizontal, Metrics.contentPadding)
        }
        .padding(.vertical, Metrics.contentPadding)
    }

    private var header: some View {
        HStack(spacing: Metrics.headerItemSpacing) {
            Button(action: onClose) {
                Image(uiImage: DesignSystemImages.Glyphs.Size24.close)
                    .padding(Metrics.closeIconPadding)
            }
            .buttonStyle(CloseButtonStyle())
            .accessibilityLabel(UserText.keyCommandClose)
            .fixedSize()

            Text(UserText.addFavoriteScreenTitle)
                .daxHeadline()
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)

            Button(UserText.actionSave, action: save)
                .daxBodyRegular()
                .foregroundColor(.white)
                .padding(.horizontal, Metrics.saveButtonHorizontalPadding)
                .padding(.vertical, Metrics.saveButtonVerticalPadding)
                .frame(minHeight: Metrics.saveButtonMinimumHeight)
                .background(Color(designSystemColor: .buttonsPrimaryDefault), in: Capsule())
                .disabled(!model.canSave)
                .opacity(!model.canSave ? 0.5 : 1)
                .fixedSize()
        }
        .padding(.horizontal, Metrics.contentPadding)
    }

    private func save() {
        guard model.canSave else { return }
        guard model.save() else {
            saveFailed = true
            return
        }
        onClose()
    }
}

private enum Metrics {
    static let contentPadding: CGFloat = 16
    static let headerToFormSpacing: CGFloat = 16
    static let headerItemSpacing: CGFloat = 8
    static let fieldVerticalPadding: CGFloat = 15
    static let dividerHeight: CGFloat = 0.5
    static let formCornerRadius: CGFloat = 24
    static let closeIconPadding: CGFloat = 4
    static let saveButtonHorizontalPadding: CGFloat = 14
    static let saveButtonVerticalPadding: CGFloat = 8
    static let saveButtonMinimumHeight: CGFloat = 40
}
