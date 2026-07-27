//
//  TapAllowHintOverlayPlayground.swift
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
import DesignResourcesKit
import UIComponents

/// Debug harness that renders a hand-built mock of the system "Add VPN Configurations" permission dialog in
/// both the iOS 26 and iOS 18 visual styles, with ``FloatingPointerBubble`` laid on top using the same
/// screen-centre-relative offsets as `TapAllowHintOverlayWindow`. The real dialog can't be summoned or styled
/// on demand, so this lets us eyeball and tune the hint alignment without triggering the real permission
/// prompt. The sliders start at the production values and the read-out shows the numbers to copy back into
/// `TapAllowHintOverlayWindow.Metrics`. Reached from the Subscription debug menu's Onboarding section.
struct TapAllowHintOverlayPlaygroundView: View {

    /// Mirrors the production `TapAllowHintOverlayWindow.Metrics`. Kept local so this debug-only harness doesn't
    /// force that type to widen its access; copy any tuned values back into `Metrics` by hand.
    enum Metrics {
        // `FloatingPointerBubble` geometry: a 33pt arrow sits above the pill, and the pill is the 17pt
        // "Tap allow" label plus 12pt vertical padding top & bottom (~44pt).
        static let bubbleArrowHeight: CGFloat = 33
        static let bubblePillHeight: CGFloat = 44
        static let bubbleHeight: CGFloat = bubbleArrowHeight + bubblePillHeight

        static let hintOffsetX: CGFloat = -77
        static let hintOffsetYIOS26: CGFloat = 125
        static let hintOffsetYIOS18: CGFloat = 65
    }

    enum AlertStyle: String, CaseIterable, Identifiable {
        case iOS26 = "iOS 26"
        case iOS18 = "iOS 18"

        var id: String { rawValue }

        var defaultOffsetY: CGFloat {
            switch self {
            case .iOS26: return Metrics.hintOffsetYIOS26
            case .iOS18: return Metrics.hintOffsetYIOS18
            }
        }
    }

    private let onClose: () -> Void

    @State private var style: AlertStyle
    @State private var offsetX: CGFloat = Metrics.hintOffsetX
    @State private var offsetY: CGFloat

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
        let initialStyle: AlertStyle = {
            if #available(iOS 26, *) { return .iOS26 }
            return .iOS18
        }()
        _style = State(initialValue: initialStyle)
        _offsetY = State(initialValue: initialStyle.defaultOffsetY)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()

            GeometryReader { proxy in
                let centre = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)

                // Centre the mock alert by filling the space (default .center alignment) rather than `.position`,
                // which would collapse the alert's width and force the copy to wrap into a tall, narrow column.
                MockVPNPermissionAlert(style: style)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                FloatingPointerBubble(text: UserText.subscriptionOnboardingVPNActivationTapAllowHint,
                                      backgroundColor: Color(singleUseColor: .fireModeAccent))
                    .position(x: centre.x + offsetX,
                              y: centre.y + offsetY + Metrics.bubbleHeight)
            }
            .ignoresSafeArea()

            controls
        }
    }

    private var controls: some View {
        VStack {
            VStack(spacing: 12) {
                Picker("Dialog style", selection: styleBinding) {
                    ForEach(AlertStyle.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                offsetSlider("Offset X", value: $offsetX, range: -150...150)
                offsetSlider("Offset Y", value: $offsetY, range: 0...260)

                HStack {
                    Button("Reset to \(style.rawValue)") { resetOffsets(for: style) }
                    Spacer()
                    Button("Close", action: onClose)
                }
                .font(.system(size: 15, weight: .semibold))
            }
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(16)

            Spacer()
        }
    }

    // Resets the offsets to the production defaults whenever the style changes, so each style shows its
    // shipped positioning until the developer starts tuning.
    private var styleBinding: Binding<AlertStyle> {
        Binding(get: { style }, set: { newStyle in
            style = newStyle
            resetOffsets(for: newStyle)
        })
    }

    private func resetOffsets(for style: AlertStyle) {
        offsetX = Metrics.hintOffsetX
        offsetY = style.defaultOffsetY
    }

    private func offsetSlider(_ title: String, value: Binding<CGFloat>, range: ClosedRange<CGFloat>) -> some View {
        HStack {
            Text("\(title): \(Int(value.wrappedValue))")
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .frame(width: 96, alignment: .leading)
            Slider(value: value, in: range)
        }
    }
}

/// Visual approximation of the system "Add VPN Configurations" dialog. Deliberately uses system fonts/colours
/// (not the app design system) so it mirrors the OS chrome the hint has to line up with. The two styles differ
/// structurally: iOS 26 adds an app icon on top and uses filled capsule buttons, while iOS 18 and earlier use
/// the classic hairline-divided text buttons — which is why the "Allow" target sits at a different offset.
private struct MockVPNPermissionAlert: View {
    /// Verbatim copy of the real system "Add VPN Configurations" dialog, identical across both mock styles.
    /// This is OS-owned text, not app copy — iOS renders it in the user's system language itself, so it's
    /// intentionally not routed through `UserText`/localization here.
    private enum Verbatim {
        static let title = "“DuckDuckGo” Would Like to Add VPN Configurations"
        static let description = "All network activity on this iPhone may be filtered or monitored when using VPN."
        static let allow = "Allow"
        static let dontAllow = "Don’t Allow"
    }

    let style: TapAllowHintOverlayPlaygroundView.AlertStyle

    var body: some View {
        switch style {
        case .iOS26: modernAlert
        case .iOS18: legacyAlert
        }
    }

    // iOS 26 Liquid Glass
    private var modernAlert: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(.debugSystemVPN77)
                .resizable()
                .frame(width: 74, height: 77)

            VStack(alignment: .leading, spacing: 10) {
                Text(Verbatim.title)
                    .font(.system(size: 17, weight: .semibold))
                Text(Verbatim.description)
                    .font(.system(size: 17, weight: .regular))
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity)
            .padding(8)

            HStack(spacing: 16) {
                capsuleButton(Verbatim.allow, emphasised: false)
                capsuleButton(Verbatim.dontAllow, emphasised: true)
            }
        }
        .padding(14)
        .frame(width: 300, alignment: .top)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
    }

    // iOS 18 and earlier
    private var legacyAlert: some View {
        VStack(spacing: 0) {
            VStack(spacing: 9) {
                Text(Verbatim.title)
                    .font(.system(size: 17, weight: .semibold))
                Text(Verbatim.description)
                    .font(.system(size: 13))
            }
            .foregroundColor(.black)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(20)

            Rectangle()
                .fill(Color.black.opacity(0.24))
                .frame(height: 0.5)

            HStack(spacing: 0) {
                Text(Verbatim.allow)
                    .fontWeight(.regular)
                    .frame(maxWidth: .infinity, minHeight: 44)

                Rectangle()
                    .fill(Color.black.opacity(0.24))
                    .frame(width: 0.5, height: 44)

                Text(Verbatim.dontAllow)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .font(.system(size: 17))
            .foregroundColor(Color(0x3969EF))
        }
        .frame(width: 270)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // Design spec: equal-width capsule (border-radius 100) filling the row, 48pt tall, 17pt Medium copy.
    // "Allow" uses the system secondary-fill gray (rgba(120,120,128,0.16)); "Don't Allow" uses the design's
    // accent blue (#0088FF).
    private func capsuleButton(_ title: String, emphasised: Bool) -> some View {
        Text(title)
            .font(.system(size: 17, weight: .medium))
            .tracking(-0.43)
            .foregroundColor(emphasised ? .white : Color.black.opacity(0.84))
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(emphasised ? Color(0x0088FF) : Color(0x787880, opacity: 0.16))
            .clipShape(Capsule())
    }
}
