//
//  SwitchBarButtonsView.swift
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
import UIKit
import DesignResourcesKitIcons

enum SwitchBarButtonState {
    case noButtons
    case clearOnly

    var showsClearButton: Bool {
        switch self {
        case .noButtons:
            return false
        case .clearOnly:
            return true
        }
    }
}

struct SwitchBarButtonsView: View {
    let buttonState: SwitchBarButtonState
    let onClearTapped: () -> Void

    private enum Constants {
        static let buttonSize: CGFloat = 24
        static let buttonSpacing: CGFloat = 6
    }

    var body: some View {
        HStack(spacing: Constants.buttonSpacing) {
            Spacer()
            if buttonState.showsClearButton {
                Button(action: onClearTapped) {
                    Image(uiImage: DesignSystemImages.Glyphs.Size24.clear)
                        .foregroundColor(Color(.systemGray))
                        .frame(width: Constants.buttonSize, height: Constants.buttonSize)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .frame(height: Constants.buttonSize)
        .opacity(buttonState.showsClearButton ? 1 : 0)
    }
}
