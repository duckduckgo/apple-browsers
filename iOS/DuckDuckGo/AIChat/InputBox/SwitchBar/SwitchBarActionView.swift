//
//  SwitchBarActionView.swift
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

struct SwitchBarActionView: View {
    let hasText: Bool
    let forceWebSearchEnabled: Bool
    let onWebSearchToggle: () -> Void
    let onSend: () -> Void

    var body: some View {
        HStack {
            Spacer()

            Button(action: onWebSearchToggle) {
                Image(systemName: "globe")
                    .font(.system(size: 18))
                    .foregroundColor(forceWebSearchEnabled ? .white : .primary)
                    .frame(width: 44, height: 44)
                    .background(forceWebSearchEnabled ? Color.accentColor : Color.secondary.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(PlainButtonStyle())

            if hasText {
                Button(action: onSend) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.accentColor)
                        .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .animation(.easeInOut(duration: 0.2), value: hasText)
    }
}

#Preview {
    SwitchBarActionView(
        hasText: true,
        forceWebSearchEnabled: false,
        onWebSearchToggle: { print("Web search toggled") },
        onSend: { print("Send tapped") }
    )
}
