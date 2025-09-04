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
        VStack(spacing: 20) {
            ContentView()
            CTAView(onDismiss: onDismiss)
                .frame(maxWidth: 440)
                .padding(.horizontal, 32)
        }
        .background(Color(designSystemColor: .background))
    }
}

private struct ContentView: View {
    var body: some View {
        ZStack {
            backgroundView
            VStack {
                headerView
                    .frame(width: 300)
                animationView
            }
            .padding()
        }
    }

    var headerView: some View {
        VStack(spacing: 0) {
            Text(UserText.newAddressBarPickerTitle)
                .textCase(.uppercase)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(baseColor: .red50))
                .padding(.bottom, 8)

            Text(UserText.newAddressBarPickerSubtitle)
                .daxTitle1()
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 16)

            Text(UserText.newAddressBarPickerDescription)
                .daxCaption()
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 16)
        }
    }

    var backgroundView: some View {
        LinearGradient(
            stops: [
                Gradient.Stop(color: Color(designSystemColor: .background), location: 0.2),
                Gradient.Stop(color: Color(designSystemColor: .accent).opacity(0.6), location: 1.0),
            ],
            startPoint: UnitPoint(x: 0.5, y: 0),
            endPoint: UnitPoint(x: 0.8, y: 2.5)
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
        VStack(spacing: 0) {
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
            .padding(.bottom, 16)

            Button {
                onDismiss()
            } label: {
                Text(UserText.newAddressBarPickerConfirm)
                    .daxButton()
                    .foregroundStyle(Color(designSystemColor: .accentContentPrimary))

            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.bottom, 8)

            Button {
                onDismiss()
            } label: {
                Text(UserText.newAddressBarPickerNotNow)
                    .daxButton()
                    .foregroundStyle(Color(designSystemColor: .accent))

            }
            .buttonStyle(SecondaryButtonStyle())
            .padding(.bottom, 16)

            Text(UserText.newAddressBarPickerFooter)
                .daxCaption()
                .foregroundColor(Color(designSystemColor: .textSecondary))
                .multilineTextAlignment(.center)
                .padding(.bottom, 10)
        }
    }
}
