//
//  NewAddressBarPickerContentView.swift
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
import UIComponents
import DesignResourcesKit
import DuckUI

struct NewAddressBarPickerContentView: View {
    let onDismiss: () -> Void

    init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }

    var body: some View {
        VStack(spacing: 24) {
            ContentView()
            CTAView(onDismiss: onDismiss)
                .padding(.horizontal, 32)
        }
        .background(Color(designSystemColor: .background))
    }
}

private struct ContentView: View {
    var body: some View {
        ZStack {
            backgroundView
            VStack(spacing: 16) {
                headerView
                animationView
            }
            .padding()
        }
    }

    var headerView: some View {
        VStack(spacing: 8) {
            Text(UserText.newAddressBarPickerTitle)
                .textCase(.uppercase)
                .daxTitle1()
                .foregroundColor(.secondary)
            
            Text(UserText.newAddressBarPickerSubtitle)
                .daxCaption()
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
            
            Text(UserText.newAddressBarPickerDescription)
                .daxCaption()
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    var backgroundView: some View {
        LinearGradient(
            stops: [
                Gradient.Stop(color: Color(designSystemColor: .background), location: 0.2),
                Gradient.Stop(color: Color(designSystemColor: .accent).opacity(0.4), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var animationView: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(designSystemColor: .accent).opacity(0.2))
            .frame(height: 120)
            .overlay(
                Text("Animation Placeholder")
                    .daxCaption()
                    .foregroundColor(.secondary)
            )
    }
}


private struct CTAView: View {
    let onDismiss: () -> Void
    @State private var selectedOption: Int = 0
    
    var body: some View {
        VStack(spacing: 20) {
            RadioButtonView(
                options: [
                    UserText.newAddressBarPickerSearchOnly,
                    UserText.newAddressBarPickerSearchAndAI
                ],
                selectedIndex: selectedOption,
                configuration: RadioButtonConfiguration(
                    layout: .horizontal
                )
            ) { _, selectedIndex in
                if let index = selectedIndex {
                    self.selectedOption = index
                }
            }

            Button {
                onDismiss()
            } label: {
                Text(UserText.newAddressBarPickerConfirm)
                    .daxButton()
                    .foregroundStyle(Color(designSystemColor: .accentContentPrimary))

            }
            .buttonStyle(PrimaryButtonStyle())

            Button {
                onDismiss()
            } label: {
                Text(UserText.newAddressBarPickerNotNow)
                    .daxButton()
                    .foregroundStyle(Color(designSystemColor: .accent))

            }
            .buttonStyle(SecondaryButtonStyle())

            // Footer Text
            Text(UserText.newAddressBarPickerFooter)
                .daxCaption()
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}
