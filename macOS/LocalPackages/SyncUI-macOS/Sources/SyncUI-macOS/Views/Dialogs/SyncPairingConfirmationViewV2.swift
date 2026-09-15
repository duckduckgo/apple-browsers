//
//  SyncPairingConfirmationViewV2.swift
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
import SwiftUIExtensions

public struct SyncPairingConfirmationViewV2: View {

    private let title: String
    private let message: String
    private let cancelButtonTitle: String
    private let confirmButtonTitle: String
    private let onCancel: () -> Void
    private let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss

    public init(
        title: String,
        message: String,
        cancelButtonTitle: String,
        confirmButtonTitle: String,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.cancelButtonTitle = cancelButtonTitle
        self.confirmButtonTitle = confirmButtonTitle
        self.onCancel = onCancel
        self.onConfirm = onConfirm
    }

    public var body: some View {
        SyncDialogV2(spacing: 10.0) {
            VStack(spacing: 20) {
                Image(nsImage: DesignSystemImages.Color.Size32.duckDuckGo)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 48, height: 48)
                    .accessibilityHidden(true)

                Text(title)
                    .font(.title2.weight(.semibold))
                    .foregroundColor(Color(designSystemColor: .textPrimary))

                Text(message)
                    .font(.body)
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 20)
        } buttons: {
            Spacer()

            Button(cancelButtonTitle) {
                onCancel()
                dismiss()
            }
            .buttonStyle(DismissActionButtonStyle(stateColors: .themedDismissButton))
            .keyboardShortcut(.cancelAction)

            Button(confirmButtonTitle) {
                onConfirm()
                dismiss()
            }
            .buttonStyle(DefaultActionButtonStyle(enabled: true, stateColors: .themedActionButton))
            .keyboardShortcut(.defaultAction)
        }
    }
}

#if DEBUG
#Preview("Default") {
    DesignSystemRebrand.isAppRebranded = { true }
    return SyncPairingConfirmationViewV2(
        title: "Sync new device?",
        message: "\"Dax’s iPhone\" will be able to access your synced DuckDuckGo passwords, autofill data, and Duck.ai chats.",
        cancelButtonTitle: "Cancel",
        confirmButtonTitle: "Sync Now",
        onCancel: {},
        onConfirm: {}
    )
}

#Preview("Long Device Name") {
    DesignSystemRebrand.isAppRebranded = { true }
    return SyncPairingConfirmationViewV2(
        title: "Sync new device?",
        message: "\"Dax’s Very Long MacBook Pro Device Name\" will be able to access your synced DuckDuckGo passwords, autofill data, and Duck.ai chats.",
        cancelButtonTitle: "Cancel",
        confirmButtonTitle: "Sync Now",
        onCancel: {},
        onConfirm: {}
    )
}
#endif
