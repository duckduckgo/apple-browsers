//
//  AutofillSettingsView.swift
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

struct AutofillSettingsView: View {
    
    @ObservedObject var viewModel: AutofillSettingsViewModel
    
    var body: some View {
        List {
            Section {
                Button {
                    viewModel.navigateToPasswords()
                } label: {
                    HStack {
                        Image(.key24)
                            .foregroundColor(Color(designSystemColor: .textPrimary))
                        Text(UserText.autofillLoginListTitle)
                            .daxBodyRegular()
                            .foregroundColor(Color(designSystemColor: .textPrimary))
                        
                        Spacer()
                        
                        if let passwordsCount = viewModel.passwordsCount {
                            Text("\(passwordsCount)")
                                .daxBodyRegular()
                                .foregroundColor(Color(designSystemColor: .textSecondary))
                        }
                        
                        Image(systemName: "chevron.forward")
                            .font(Font.system(.footnote).weight(.bold))
                            .foregroundColor(Color(UIColor.tertiaryLabel))
                    }
                }
            }
            
            Section(footer: PasswordFooterView(viewModel: viewModel)) {
                Toggle(UserText.autofillSettingsAskToSaveAndAutofill, isOn: $viewModel.savePasswordsEnabled)
                    .toggleStyle(.switch)
                    .tint(Color(designSystemColor: .accent))
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                    .daxBodyRegular()
            }
            
            Section(header: Text(UserText.autofillSettingsImportPasswordsSectionHeader).foregroundColor(.secondary)) {
                if #available(iOS 18.2, *) {
                    Button {
                        viewModel.navigateToFileImport()
                    } label: {
                        Text(UserText.autofillEmptyViewImportButtonTitle)
                            .daxBodyRegular()
                            .foregroundColor(Color(designSystemColor: .accent))
                    }
                    Button {
                        viewModel.navigateToImportViaSync()
                    } label: {
                        Text(UserText.autofillEmptyViewImportViaSyncButtonTitle)
                            .daxBodyRegular()
                            .foregroundColor(Color(designSystemColor: .accent))
                    }
                } else {
                    Button {
                        viewModel.navigateToImportViaSync()
                    } label: {
                        Text(UserText.autofillEmptyViewImportButtonTitle)
                            .daxBodyRegular()
                            .foregroundColor(Color(designSystemColor: .accent))
                    }
                }
            }
            
            if viewModel.shouldShowNeverPromptReset() {
                Section(header: Text(UserText.autofillSettingsOptionsSectionHeader).foregroundColor(.secondary)) {
                    Button {
                        viewModel.resetExcludedSites()
                    } label: {
                        Text(UserText.autofillNeverSavedSettings)
                            .foregroundColor(Color(designSystemColor: .accent))
                    }
                }
            }

        }
        .applyInsetGroupedListStyle()
        .confirmationDialog(
            "",
            isPresented: $viewModel.showingResetConfirmation,
            titleVisibility: .hidden
        ) {
            Button(UserText.autofillResetNeverSavedActionConfirmButton, role: .destructive) {
                viewModel.confirmResetExcludedSites()
            }
            Button(UserText.autofillResetNeverSavedActionCancelButton, role: .cancel) {
                viewModel.cancelResetExcludedSites()
            }
        } message: {
            Text(UserText.autofillResetNeverSavedActionTitle)
        }
        .onAppear {
            viewModel.updatePasswordsCount()
        }
    }
    
    private struct PasswordFooterView: View {
        let viewModel: AutofillSettingsViewModel
        
        var body: some View {
            return (Text(Image(.lockSolid16)).baselineOffset(-1.0).foregroundColor(.secondary)
                    + Text(verbatim: " ")
                    + Text(UserText.autofillLoginListSettingsFooter).foregroundColor(.secondary)
                    + Text(verbatim: " ")
                    + Text(viewModel.footerAttributedString())
            )
            .daxFootnoteRegular()
            .lineSpacing(2)
        }
    }
}

#Preview {
    AutofillSettingsView(viewModel: AutofillSettingsViewModel(source: .settings))
}
