//
//  AutofillItemsEmptyView.swift
//  DuckDuckGo
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
import DuckUI
import MetricBuilder
import Core

struct AutofillItemsEmptyView: View {

    var importButtonAction: (() -> Void)?
    var importViaSyncButtonAction: (() -> Void)?

    var body: some View {
        VStack(spacing: 8) {
            Image(rebrandable: "Passwords-Add-96x96")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 96, height: 96)

            VStack(spacing: 4) {
                Text(UserText.autofillEmptyViewTitle)
                    .daxTitle3()
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)

                Text(UserText.autofillEmptyViewSubtitle)
                    .daxBodyRegular()
                    .foregroundColor(Color(designSystemColor: .textSecondary))
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)

            VStack(spacing: ButtonStackMetrics.interButtonSpacing) {
                if #available(iOS 18.2, *) {
                    Button {
                        importButtonAction?()
                    } label: {
                        Text(UserText.autofillEmptyViewImportButtonTitle)
                    }
                    .buttonStyle(PrimaryButtonStyle(compact: true))
                    .onFirstAppear {
                        if case .hub = DataImportEntryPointHandler().destination(for: .passwords) {
                            Pixel.fire(pixel: .importHubEntryShown, withAdditionalParameters: DataImportViewModel.ImportScreen.passwords.importHubEntryPointParameters)
                        } else {
                            Pixel.fire(pixel: .autofillImportPasswordsImportButtonShown)
                        }
                    }

                    Button {
                        importViaSyncButtonAction?()
                    } label: {
                        Text(UserText.autofillEmptyViewImportViaSyncButtonTitle)
                    }
                    .buttonStyle(SecondaryFillButtonStyle(compact: true))
                } else {
                    Button {
                        importViaSyncButtonAction?()
                    } label: {
                        Text(UserText.autofillEmptyViewImportButtonTitle)
                    }
                    .buttonStyle(PrimaryButtonStyle(compact: true))
                }
            }
            // fixedSize sizes both buttons to the wider title's width.
            .fixedSize(horizontal: true, vertical: false)
            .padding(8)
        }
        .frame(maxWidth: 300.0)
        .padding(16)
    }

}

#Preview {
    AutofillItemsEmptyView()
}
