//
//  AutofillLoginDetailsView.swift
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
import DuckUI
import DesignResourcesKit
import DesignResourcesKitIcons

struct AutofillLoginDetailsView: View {
    @ObservedObject var viewModel: AutofillLoginDetailsViewModel
    @State private var actionSheetConfirmDeletePresented: Bool = false

    var body: some View {
        list
            .alert(isPresented: $viewModel.isShowingAddressUpdateConfirmAlert) {
                let btnLabel = Text(viewModel.toggleConfirmationAlert.button)
                let btnAction = viewModel.togglePrivateEmailStatus
                let button = Alert.Button.default(btnLabel, action: btnAction)
                let cancelBtnLabel = Text(UserText.autofillCancel)
                let cancelBtnAction = { viewModel.refreshprivateEmailStatusBool() }
                let cancelButton = Alert.Button.cancel(cancelBtnLabel, action: cancelBtnAction)
                return Alert(
                    title: Text(viewModel.toggleConfirmationAlert.title),
                    message: Text(viewModel.toggleConfirmationAlert.message),
                    primaryButton: button,
                    secondaryButton: cancelButton)
            }

    }

    private var list: some View {
        List {
            switch viewModel.viewMode {
            case .edit:
                editingContentView
                    .listRowBackground(Color(designSystemColor: .surface))
            case .view:
                viewingContentView
            case .new:
                editingContentView
                    .listRowBackground(Color(designSystemColor: .surface))
            }
        }
        .simultaneousGesture(
            DragGesture().onChanged({_ in
                viewModel.selectedCell = nil
            }))
        .applyInsetGroupedListStyle()
        .animation(.easeInOut, value: viewModel.viewMode)
    }
    
    private var editingContentView: some View {
        Group {
            Section {
                AutofillEditableCell(title: UserText.autofillLoginDetailsLoginName,
                                     text: $viewModel.title,
                                     placeholderText: UserText.autofillLoginDetailsEditTitlePlaceholder,
                                     autoCapitalizationType: .words,
                                     disableAutoCorrection: false,
                                     inEditMode: viewModel.viewMode == .edit,
                                     selectedCell: $viewModel.selectedCell,
                                     textFieldAccessibilityIdentifier: "Field_PasswordName")
            }
            
            Section {
                AutofillEditableCell(title: UserText.autofillLoginDetailsUsername,
                                     text: $viewModel.username,
                                     placeholderText: UserText.autofillLoginDetailsEditUsernamePlaceholder,
                                     keyboardType: .emailAddress,
                                     inEditMode: viewModel.viewMode == .edit,
                                     selectedCell: $viewModel.selectedCell,
                                     textFieldAccessibilityIdentifier: "Field_Username")
                
                if viewModel.viewMode == .new {
                    AutofillEditableCell(title: UserText.autofillLoginDetailsPassword,
                                         text: $viewModel.password,
                                         placeholderText: UserText.autofillLoginDetailsEditPasswordPlaceholder,
                                         secure: true,
                                         inEditMode: viewModel.viewMode == .edit,
                                         selectedCell: $viewModel.selectedCell,
                                         textFieldAccessibilityIdentifier: "Field_Password")
                } else {
                    AutofillEditableMaskedCell(title: UserText.autofillLoginDetailsPassword,
                                               placeholderText: UserText.autofillLoginDetailsEditPasswordPlaceholder,
                                               unmaskedString: $viewModel.password,
                                               maskedString: .constant(viewModel.userVisiblePassword),
                                               isMasked: $viewModel.isPasswordHidden,
                                               selectedCell: $viewModel.selectedCell,
                                               textFieldAccessibilityIdentifier: "Field_Password")
                }
            }
            
            Section {
                AutofillEditableCell(title: UserText.autofillLoginDetailsAddress,
                                     text: $viewModel.address,
                                     placeholderText: UserText.autofillLoginDetailsEditURLPlaceholder,
                                     keyboardType: .URL,
                                     inEditMode: viewModel.viewMode == .edit,
                                     selectedCell: $viewModel.selectedCell,
                                     textFieldAccessibilityIdentifier: "Field_Address")
            }
            
            Section {
                editableMultilineCell(UserText.autofillLoginDetailsNotes,
                                      subtitle: $viewModel.notes,
                                      textFieldAccessibilityIdentifier: "Field_Notes")
            }
            
            if viewModel.viewMode == .edit {
                deleteCell()
            }
        }
    }
    
    private var viewingContentView: some View {
        Group {
            Section {
                AutofillLoginDetailsHeaderView(viewModel: viewModel.headerViewModel)
            }

            if viewModel.usernameIsPrivateEmail {
                privateEmailCredentialsSection()
            } else {
                credentialsSection()
            }

            Section {
                AutofillCopyableRow(title: UserText.autofillLoginDetailsAddress,
                             subtitle: viewModel.address,
                             selectedCell: $viewModel.selectedCell,
                             truncationMode: .middle,
                             actionTitle: UserText.autofillCopyPrompt(for: UserText.autofillLoginDetailsAddress),
                             action: { viewModel.copyToPasteboard(.address) },
                             secondaryActionTitle: viewModel.websiteIsValidUrl ? UserText.autofillOpenWebsitePrompt : nil,
                             secondaryAction: viewModel.websiteIsValidUrl ? { viewModel.openUrl() } : nil,
                             buttonImage: DesignSystemImages.Glyphs.Size24.globe,
                             buttonAccessibilityLabel: UserText.autofillOpenWebsitePrompt,
                             buttonAction: viewModel.websiteIsValidUrl ? { viewModel.openUrl() } : nil)
            }

            Section {
                AutofillCopyableRow(title: UserText.autofillLoginDetailsNotes,
                             subtitle: viewModel.notes,
                             selectedCell: $viewModel.selectedCell,
                             truncationMode: .middle,
                             multiLine: true,
                             actionTitle: UserText.autofillCopyPrompt(for: UserText.autofillLoginDetailsNotes),
                             action: {
                    viewModel.copyToPasteboard(.notes)
                })
            }

            Section {
                deleteCell()
            }
        }
    }

    private func credentialsSection() -> some View {
        Section {
            usernameCell()
            passwordCell()
        }
    }

    @ViewBuilder
    private func privateEmailCredentialsSection() -> some View {

        // If the user is not signed in, we should show the cells separately + the footer message
        if !viewModel.isSignedIn {
            Section {
                usernameCell()
            } footer: {
                if !viewModel.isSignedIn {
                    var attributedString: AttributedString {
                        let text = String(format: UserText.autofillSignInToManageEmail, UserText.autofillEnableEmailProtection)
                        var attributedString = AttributedString(text)
                        if let range = attributedString.range(of: UserText.autofillEnableEmailProtection) {
                            attributedString[range].foregroundColor = Color(ThemeManager.shared.currentTheme.buttonTintColor)
                        }
                        return attributedString
                    }
                    Text(attributedString)
                        .font(.footnote)
                        .lineLimit(nil)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .onTapGesture {
                viewModel.openPrivateEmailURL()
            }

            Section {
                passwordCell()
            }

        // If signed in, we only show the separate sections if the email is manageable
        } else if viewModel.shouldAllowManagePrivateAddress {
            Group {
                Section {
                    usernameCell()
                    privateEmailCell()
                }
                Section {
                    passwordCell()
                }
            }.transition(.opacity)

        } else {
            Section {
                credentialsSection()
            }.transition(.opacity)
        }
    }
    
    private func editableMultilineCell(_ title: String,
                                       subtitle: Binding<String>,
                                       autoCapitalizationType: UITextAutocapitalizationType = .none,
                                       disableAutoCorrection: Bool = true,
                                       keyboardType: UIKeyboardType = .default,
                                       textFieldAccessibilityIdentifier: String) -> some View {

        VStack(alignment: .leading, spacing: Constants.verticalPadding) {
            Text(title)
                .label4Style()
            
            MultilineTextEditor(text: subtitle).accessibilityIdentifier(textFieldAccessibilityIdentifier)
        }
        .frame(minHeight: Constants.minRowHeight)
        .padding(EdgeInsets(top: 6, leading: 0, bottom: 0, trailing: 0))
    }

    private func deleteCell() -> some View {
        AutofillDeleteButtonCell(deleteButtonText: UserText.autofillLoginDetailsDeleteButton,
                                 confirmationTitle: UserText.autofillDeleteAllPasswordsActionTitle(for: 1),
                                 confirmationMessage: viewModel.deleteMessage(),
                                 confirmationButtonTitle: UserText.autofillLoginDetailsDeleteButton,
                                 onDelete: {
            viewModel.delete()
        })
    }

    private func usernameCell() -> some View {
        AutofillCopyableRow(title: UserText.autofillLoginDetailsUsername,
                            subtitle: viewModel.usernameDisplayString,
                            selectedCell: $viewModel.selectedCell,
                            actionTitle: UserText.autofillCopyPrompt(for: UserText.autofillLoginDetailsUsername),
                            action: { viewModel.copyToPasteboard(.username) },
                            buttonImage: DesignSystemImages.Glyphs.Size24.copy,
                            buttonAccessibilityLabel: UserText.autofillCopyPrompt(for: UserText.autofillLoginDetailsUsername),
                            buttonAction: { viewModel.copyToPasteboard(.username) })

    }

    private func passwordCell() -> some View {
        AutofillCopyableRow(title: UserText.autofillLoginDetailsPassword,
                            subtitle: viewModel.userVisiblePassword,
                            selectedCell: $viewModel.selectedCell,
                            isMonospaced: true,
                            actionTitle: viewModel.isPasswordHidden ? UserText.autofillShowPassword : UserText.autofillHidePassword,
                            action: { viewModel.isPasswordHidden.toggle() },
                            secondaryActionTitle: UserText.autofillCopyPrompt(for: UserText.autofillLoginDetailsPassword),
                            secondaryAction: { viewModel.copyToPasteboard(.password) },
                            buttonImage: viewModel.isPasswordHidden ? DesignSystemImages.Glyphs.Size24.eye : DesignSystemImages.Glyphs.Size24.eyeClosed,
                            buttonAccessibilityLabel: viewModel.isPasswordHidden ? UserText.autofillShowPassword : UserText.autofillHidePassword,
                            buttonAction: { viewModel.isPasswordHidden.toggle() },
                            secondaryButtonImage: DesignSystemImages.Glyphs.Size24.copy,
                            secondaryButtonAccessibilityLabel: UserText.autofillCopyPrompt(for: UserText.autofillLoginDetailsPassword),
                            secondaryButtonAction: { viewModel.copyToPasteboard(.password) })
    }

    private func privateEmailCell() -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Duck Address").label4Style()
                Text(viewModel.privateEmailMessage)
                    .font(.footnote)
                    .label4Style(design: .default, foregroundColorLight: Color(baseColor: .gray50), foregroundColorDark: Color(baseColor: .gray30))

            }
            Spacer(minLength: Constants.textFieldImageSize)
            if viewModel.privateEmailStatus == .active || viewModel.privateEmailStatus == .inactive {
                Toggle("", isOn: $viewModel.privateEmailStatusBool)
                    .frame(width: 80)
                    .toggleStyle(SwitchToggleStyle(tint: Color(ThemeManager.shared.currentTheme.buttonTintColor)))
            } else {
                Image(uiImage: DesignSystemImages.Glyphs.Size16.alertRecolorable)
                    .resizable()
                    .frame(width: 20, height: 20)
                    .padding(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))

            }
        }
    }

}

private struct MultilineTextEditor: View {
    @Binding var text: String
    
    var body: some View {
        TextEditor(text: $text)
            .frame(maxHeight: .greatestFiniteMagnitude)
    }
}

private struct Constants {
    static let verticalPadding: CGFloat = 4
    static let minRowHeight: CGFloat = 60
    static let textFieldImageSize: CGFloat = 24
    static let insets = EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
}
