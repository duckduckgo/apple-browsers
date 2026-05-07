//
//  DuckAIToggleDebugView.swift
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

import SwiftUI
import UIKit
import Core

struct DuckAIToggleDebugView: View {

    @State private var isShowingCooldownAlert = false

    var body: some View {
        List {
            Section {
                Button(action: {
                    Self.markCooldownPassed()
                    isShowingCooldownAlert = true
                }, label: {
                    Text(verbatim: "Set Install Cooldown Elapsed")
                })
                .alert(isPresented: $isShowingCooldownAlert, content: {
                    Alert(title: Text(verbatim: "AI Toggle Prompt cooldown set"),
                          dismissButton: .cancel(Text(verbatim: "Done")))
                })

                Button(action: {
                    Self.resetPickerState()
                }, label: {
                    Text(verbatim: "Reset Picker State (Selection + Shown Flag)")
                })

                Button(action: {
                    Self.showTogglePrompt()
                }, label: {
                    Text(verbatim: "Show New Duck.ai Toggle Prompt")
                })
            } header: {
                Text(verbatim: "Duck.ai Toggle Prompt")
            }
        }
    }

    private static func markCooldownPassed() {
        StatisticsUserDefaults().installDate = Date().addingTimeInterval(-NewAddressBarPickerDisplayValidator.installCooldown)
    }

    private static func showTogglePrompt() {
        guard let controller = UIApplication.shared.firstKeyWindow?.rootViewController?.presentedViewController else { return }

        let pickerViewController = NewAddressBarPickerViewController(aiChatSettings: AIChatSettings())

        pickerViewController.modalPresentationStyle = pickerViewController.isPad ? .formSheet : .pageSheet
        pickerViewController.modalTransitionStyle = .coverVertical
        pickerViewController.isModalInPresentation = true

        controller.present(pickerViewController, animated: true)
    }

    private static func resetPickerState() {
        AIChatSettings().resetAIChatSearchInputUserSettings()
        NewAddressBarPickerStore().reset()

        ActionMessageView.present(message: "Picker state reset")
    }
}
