//
//  TapAllowOverlayPlaygroundView.swift
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

/// Debug harness for ``TapAllowHintOverlayWindow``: presents an alert whose text mirrors the system
/// VPN-configuration permission dialog (so its height matches) and layers the "Tap allow" hint over it, to
/// check the arrow tip lands on the Allow button across devices and OS versions.
struct TapAllowOverlayPlaygroundView: View {
    @State private var tapAllowHint = TapAllowHintOverlayWindow()

    var body: some View {
        VStack(spacing: 24) {
            Text(verbatim: "Presents a permission-style alert and layers the \"Tap allow\" hint on top. Verify the arrow tip lands on the Allow button on this device and OS version.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button(action: { showAlertWithOverlay() }) {
                Text(verbatim: "Show alert + overlay")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDisappear { tapAllowHint.hide() }
    }

    @MainActor
    private func showAlertWithOverlay() {
        guard let presenter = UIApplication.shared.firstKeyWindow?.rootViewController?.topPresentedViewController else { return }

        let alert = UIAlertController(
            title: "\"DuckDuckGo\" Would Like to Add VPN Configurations",
            message: "All network activity on this iPhone may be filtered or monitored when using VPN.",
            preferredStyle: .alert)
        let allow = UIAlertAction(title: "Allow", style: .default) { _ in tapAllowHint.hide() }
        alert.addAction(allow)
        alert.addAction(UIAlertAction(title: "Don't Allow", style: .default) { _ in tapAllowHint.hide() })
        alert.preferredAction = allow

        tapAllowHint.show()
        presenter.present(alert, animated: true)
    }
}
