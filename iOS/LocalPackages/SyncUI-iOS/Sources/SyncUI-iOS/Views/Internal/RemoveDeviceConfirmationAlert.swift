//
//  RemoveDeviceConfirmationAlert.swift
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

struct RemoveDeviceConfirmationAlert: ViewModifier {

    @Binding var isPresented: Bool
    let deviceName: String
    let isImprovedPairingFlowEnabled: Bool
    let onConfirm: () -> Void

    func body(content: Content) -> some View {
        content.alert(title, isPresented: $isPresented) {
            Button(UserText.cancelButton, role: .cancel) {}
            Button(confirmButtonTitle, role: .destructive, action: onConfirm)
        } message: {
            Text(message)
        }
    }

    private var title: String {
        isImprovedPairingFlowEnabled ? UserText.simplifiedRemoveDeviceConfirmTitle(deviceName) : UserText.removeDeviceTitle
    }

    private var message: String {
        isImprovedPairingFlowEnabled ? UserText.simplifiedRemoveDeviceConfirmMessage(deviceName) : UserText.removeDeviceMessage(deviceName)
    }

    private var confirmButtonTitle: String {
        isImprovedPairingFlowEnabled ? UserText.simplifiedRemoveDeviceConfirmAction : UserText.removeDeviceButton
    }
}

extension View {

    func removeDeviceConfirmationAlert(isPresented: Binding<Bool>,
                                       deviceName: String,
                                       isImprovedPairingFlowEnabled: Bool,
                                       onConfirm: @escaping () -> Void) -> some View {
        modifier(RemoveDeviceConfirmationAlert(isPresented: isPresented,
                                               deviceName: deviceName,
                                               isImprovedPairingFlowEnabled: isImprovedPairingFlowEnabled,
                                               onConfirm: onConfirm))
    }
}
