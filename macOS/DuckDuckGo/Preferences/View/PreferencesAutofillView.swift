//
//  PreferencesAutofillView.swift
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

import PixelKit
import PreferencesUI_macOS
import SwiftUI
import SwiftUIExtensions

extension Preferences {

    struct AutofillView: View {
        @ObservedObject var model: AutofillPreferencesModel
        @State private var showingResetNeverPromptSitesSheet = false

        var isAutoLockEnabledBinding: Binding<Bool> {
            .init {
                model.isAutoLockEnabled
            } set: { newValue in
                model.authorizeAutoLockSettingsChange(isEnabled: newValue)
            }
        }

        var autoLockThresholdBinding: Binding<AutofillAutoLockThreshold> {
            .init {
                model.autoLockThreshold
            } set: { newValue in
                model.authorizeAutoLockSettingsChange(threshold: newValue)
            }
        }

        var body: some View {
            PreferencePane(UserText.passwordManagementTitle) {

                if model.showSyncPromo {
                    SyncPromoView(viewModel: model.syncPromoViewModel, layout: .horizontal)
                        .onAppear {
                            model.syncPromoViewModel.promoDisplayed()
                        }
                }

                // Autofill Content  Button
                PreferencePaneSection(spacing: 12) {
                    Button(UserText.autofillViewContentButtonPasswords) {
                        model.showAutofillPopover(.logins, source: .settings)
                    }
                    Button(UserText.autofillViewContentButtonIdentities) {
                        model.showAutofillPopover(.identities, source: .settings)
                    }
                    Button(UserText.autofillViewContentButtonCreditCards) {
                        model.showAutofillPopover(.cards, source: .settings)
                    }
                    Button(UserText.importPasswords) {
                        model.openImportPasswordsWindow()
                    }
                    Button(UserText.exportLogins) {
                        model.openExportLogins()
                    }

                    Text(UserText.autofillContentStoredSecurelyInfo)
                        .foregroundColor(Color(.textSecondary))
                }

                // SECTION 2: Ask to Save:
                PreferencePaneSection {
                    TextMenuItemHeader(UserText.autofillAskToSave)
                    VStack(alignment: .leading, spacing: 6) {
                        ToggleMenuItem(UserText.autofillPasswords, isOn: $model.askToSaveUsernamesAndPasswords)
                        ToggleMenuItem(UserText.autofillAddresses, isOn: $model.askToSaveAddresses)
                        ToggleMenuItem(UserText.autofillCreditCards, isOn: $model.askToSavePaymentMethods)
                    }
                    .disabled(model.isManagedByExtension)
                    TextMenuItemCaption(UserText.autofillAskToSaveExplanation)
                }

                // SECTION 3: Reset excluded (aka never prompt to save) sites:
                // This is only displayed if the user has never prompt sites saved & not using Bitwarden
                if model.hasNeverPromptWebsites && model.passwordManager == .duckduckgo {
                    PreferencePaneSection {
                        TextMenuItemHeader(UserText.autofillExcludedSites)
                        TextMenuItemCaption(UserText.autofillExcludedSitesExplanation)
                            .padding(.top, -8)
                        Button(UserText.autofillExcludedSitesReset) {
                            showingResetNeverPromptSitesSheet.toggle()
                            if showingResetNeverPromptSitesSheet {
                                PixelKit.fire(GeneralPixel.autofillLoginsSettingsResetExcludedDisplayed)
                            }
                        }
                    }.sheet(isPresented: $showingResetNeverPromptSitesSheet) {
                        ResetNeverPromptSitesSheet(autofillPreferencesModel: model, isSheetPresented: $showingResetNeverPromptSitesSheet)
                    }
                }

                // SECTION 4: Auto-Lock:

                PreferencePaneSection {
                    TextMenuItemHeader(UserText.autofillAutoLock)
                    Picker(selection: isAutoLockEnabledBinding, content: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(UserText.autofillLockWhenIdle)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .multilineTextAlignment(.leading)
                                NSPopUpButtonView(selection: autoLockThresholdBinding) {
                                    let button = NSPopUpButton()
                                    button.setContentHuggingPriority(.defaultHigh, for: .horizontal)

                                    for threshold in AutofillAutoLockThreshold.allCases {
                                        let item = button.menu?.addItem(withTitle: threshold.title, action: nil, keyEquivalent: "")
                                        item?.representedObject = threshold
                                    }
                                    return button
                                }.disabled(!model.isAutoLockEnabled)
                            }
                            // We have to use a custom toggle here, as with a SwiftUI Toggle on macOS 10.x to 13.x, the checkbox gets rendered
                            // to the right when inside a picker 🤷
                            NativeCheckboxToggle(isOn: $model.autolockLocksFormFilling, label: UserText.autolockLocksFormFill)
                                .disabled(!model.isAutoLockEnabled)
                                .padding(.bottom, 6)
                        }.tag(true)
                        Text(UserText.autofillNeverLock).tag(false)
                    }, label: {})
                    .pickerStyle(.radioGroup)
                    .rebrandedControlTint()
                    .offset(x: PreferencesUI_macOS.Const.pickerHorizontalOffset)
                    TextMenuItemCaption(UserText.autofillNeverLockWarning)
                }
                .disabled(model.isManagedByExtension)

                if Application.appDelegate.featureFlagger.isFeatureOn(.autofillPasswordsStatusBar) {
                    // SECTION 5: Menu Bar
                    PreferencePaneSection {
                        TextMenuItemHeader(UserText.passwordsMenuBarSection)
                        ToggleMenuItem(UserText.showPasswordsInMenuBar, isOn: $model.showInMenuBar)
                    }
                }
            }
            .onAppear {
                model.viewDidAppear()
            }
        }

        private var shouldShowImportExportButtons: Bool {
            return model.passwordManager == .duckduckgo
        }
    }
}

struct BitwardenDowngradeInfoView: View, PreferencesTabOpening {
    var windowControllersManager: WindowControllersManagerProtocol {
        Application.appDelegate.windowControllersManager
    }

    var body: some View {
        VStack(alignment: .leading) {
            VStack(alignment: .leading) {
                HStack {
                    Text(verbatim: "1.")
                    Button(UserText.bitwardenIncompatibleStep1, action: {
                        openNewTab(with: URL(string: "https://github.com/bitwarden/clients/releases/download/desktop-mac-v2025.4.2/Bitwarden-2025.4.2-universal.dmg")!)
                    }).foregroundColor(.accentColor)
                }
                Text(UserText.bitwardenIncompatibleStep2)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct ResetNeverPromptSitesSheet: View {

    @ObservedObject var autofillPreferencesModel: AutofillPreferencesModel
    @Binding var isSheetPresented: Bool

    var body: some View {
        VStack(alignment: .center) {
            TextMenuTitle(UserText.autofillExcludedSitesResetActionTitle)
                .padding(.top, 10)

            Text(UserText.autofillExcludedSitesResetActionMessage)
                .padding(.vertical, 10)
                .padding(.horizontal, 20)
                .frame(width: 300)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            HStack(alignment: .center) {
                Spacer()
                Button(UserText.cancel) {
                    isSheetPresented.toggle()
                    PixelKit.fire(GeneralPixel.autofillLoginsSettingsResetExcludedDismissed)
                }
                Button(action: {
                    saveChanges()
                }, label: {
                    Text(UserText.autofillExcludedSitesReset)
                        .foregroundColor(.red)
                })
            }.padding(EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 15))

        }
        .padding(.vertical, 10)
    }

    private func saveChanges() {
        autofillPreferencesModel.resetNeverPromptWebsites()
        isSheetPresented.toggle()
        PixelKit.fire(GeneralPixel.autofillLoginsSettingsResetExcludedConfirmed)
    }

}
