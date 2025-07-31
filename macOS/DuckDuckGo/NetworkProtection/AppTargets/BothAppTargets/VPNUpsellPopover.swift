//
//  VPNUpsellPopover.swift
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

import AppKit
import SwiftUI
import Carbon.HIToolbox
import Lottie
import DesignResourcesKit

// MARK: - ViewModel

final class VPNUpsellPopoverViewModel {
    let title: String
    let message: String
    let image: NSImage
    let primaryButtonText: String
    let primaryButtonAction: () -> Void
    let secondaryButtonText: String
    let secondaryButtonAction: () -> Void

    init(title: String = "Secure Your Connection",
         message: String = "Get DuckDuckGo VPN to protect your browsing on any network and hide your location from websites.",
         image: NSImage = NSImage(named: "VPNIcon") ?? NSImage(),
         primaryButtonText: String = "Get VPN",
         primaryButtonAction: @escaping () -> Void,
         secondaryButtonText: String = "Not Now",
         secondaryButtonAction: @escaping () -> Void) {

        self.title = title
        self.message = message
        self.image = image
        self.primaryButtonText = primaryButtonText
        self.primaryButtonAction = primaryButtonAction
        self.secondaryButtonText = secondaryButtonText
        self.secondaryButtonAction = secondaryButtonAction
    }
}

// MARK: - SwiftUI View

struct VPNUpsellPopoverView: View {
    private let viewModel: VPNUpsellPopoverViewModel

    init(viewModel: VPNUpsellPopoverViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        VStack(spacing: 20) {
            // Top animation
            LottieView(animation: .named("privacypro_devices"))
                .playing(loopMode: .playOnce)
                .frame(width: 256, height: 96)
                .clipped()

            VStack(spacing: 16) {
                // Title and subtitle
                VStack(spacing: 4) {
                    Text("A VPN to secure your\nWi-Fi & personal info")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(Color(designSystemColor: .textPrimary))
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)

                    Text("+2 more premium protections")
                        .font(.subheadline)
                        .foregroundColor(Color(designSystemColor: .textSecondary))
                        .multilineTextAlignment(.center)
                }

                // Feature list
                VStack(alignment: .leading, spacing: 8) {
                    FeatureRow(text: "Hide your IP address from sites")
                    FeatureRow(text: "Shield your online activity from others")
                    FeatureRow(text: "Block harmful sites & online scams")

                    // PLUS section
                    HStack {
                        Spacer()
                        Text("PLUS")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(Color(designSystemColor: .textSecondary))
                        Spacer()
                    }
                    .padding(.vertical, 4)

                    FeatureRow(text: "Restore your identity if it's stolen")
                    FeatureRow(text: "Remove info from sites that sell it",
                             subtitle: "(currently available on Mac & Windows)")
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Action buttons
                HStack(spacing: 12) {
                    Button("No Thanks") {
                        viewModel.secondaryButtonAction()
                    }
                    .buttonStyle(VPNSecondaryButtonStyle())

                    Button("Try For Free") {
                        viewModel.primaryButtonAction()
                    }
                    .buttonStyle(VPNPrimaryButtonStyle())
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(24)
        .frame(width: 380)
        .background(Color(designSystemColor: .surface))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Feature Row

private struct FeatureRow: View {
    let text: String
    let subtitle: String?

    init(text: String, subtitle: String? = nil) {
        self.text = text
        self.subtitle = subtitle
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Checkmark
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(designSystemColor: .accent))
                .frame(width: 16, height: 16)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(text)
                    .font(.body)
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(Color(designSystemColor: .textSecondary))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Button Styles

private struct VPNPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(Color(designSystemColor: .buttonsPrimaryText))
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Color(designSystemColor: .buttonsPrimaryDefault))
            .cornerRadius(8)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

private struct VPNSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(Color(designSystemColor: .buttonsSecondaryFillText))
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Color(designSystemColor: .buttonsSecondaryFillDefault))
            .cornerRadius(8)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - NSPopover

final class VPNUpsellPopover: NSPopover {
    private static let topInset: CGFloat = 22

    init(viewController: NSHostingController<some View>) {
        super.init()

        behavior = .semitransient
        contentViewController = viewController
    }

    required init?(coder: NSCoder) {
        fatalError("VPNUpsellPopover: Bad initializer")
    }

    override func keyDown(with event: NSEvent) {
        if Int(event.keyCode) == kVK_Escape {
            performClose(nil)
        } else {
            super.keyDown(with: event)
        }
    }
}

// MARK: - Preview

#Preview {
    VPNUpsellPopoverView(viewModel: VPNUpsellPopoverViewModel(
        primaryButtonAction: {},
        secondaryButtonAction: {}
    ))
}
