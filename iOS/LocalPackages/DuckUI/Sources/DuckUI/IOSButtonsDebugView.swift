//
//  IOSButtonsDebugView.swift
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

#if DEBUG

import SwiftUI
import DesignResourcesKit

/// Recreates the "iOS Buttons" frame from the Mobile - New Design Language Figma file
/// (node 888:58029) using only DuckUI `ButtonStyle` instances. The "Pressed" column
/// relies on each style's `pressed: Bool` init parameter so the press state can be
/// rendered statically (SwiftUI doesn't let us synthesize a pressed
/// `ButtonStyleConfiguration` from outside).
private struct IOSButtonsDebugView: View {
    @StateObject private var override: RebrandPreviewOverride

    init() {
        _override = StateObject(wrappedValue: RebrandPreviewOverride(isRebranded: true))
    }

    private let iconName = "face.smiling"

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 56) {
                Text("iOS Buttons")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundColor(Color(designSystemColor: .textPrimary))

                HStack(alignment: .top, spacing: 32) {
                    sizeColumn
                    typeColumn
                    iconColumn
                    statesColumn
                }
            }
            .padding(48)
        }
        .background(Color(designSystemColor: .background))
    }

    // MARK: Reusable column pieces

    private func columnHeader(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(Color(designSystemColor: .textPrimary))
            Rectangle()
                .fill(Color(designSystemColor: .lines))
                .frame(height: 1)
        }
        .padding(.bottom, 4)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundColor(Color(designSystemColor: .textPrimary))
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Size column

    private var sizeColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            columnHeader("Size")
            caption("Small\nHeight: 40pts\nFont style: Button Small")
            Button("Small") {}
                .buttonStyle(SecondaryFillButtonStyle(compact: true, fullWidth: false))
            Spacer().frame(height: 8)
            caption("Large\nHeight: 50pts\nFont style: Button Large")
            Button("Large") {}
                .buttonStyle(SecondaryFillButtonStyle(fullWidth: false))
        }
        .frame(width: 280, alignment: .leading)
    }

    // MARK: Type column (compact / small height)

    private var typeColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            columnHeader("Type")
            caption("Available in 4 active levels")

            Button("Brand") {}
                .buttonStyle(BrandButtonStyle(compact: true, fullWidth: false))
            Button("Default") {}
                .buttonStyle(PrimaryButtonStyle(compact: true, fullWidth: false))
            Button("Secondary") {}
                .buttonStyle(SecondaryFillButtonStyle(compact: true, fullWidth: false))
            Button("Ghost") {}
                .buttonStyle(GhostButtonStyle(compact: true))
                .fixedSize(horizontal: true, vertical: false)

            Spacer().frame(height: 16)
            caption("3 destructive levels")

            Button("Destructive") {}
                .buttonStyle(PrimaryDestructiveButtonStyle(compact: true, fullWidth: false))
            Button("Destructive Secondary") {}
                .buttonStyle(SecondaryDestructiveButtonStyle(compact: true, fullWidth: false))
            Button("Destructive Ghost") {}
                .buttonStyle(DestructiveGhostButtonStyle(compact: true))
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(width: 280, alignment: .leading)
    }

    // MARK: Icon column (small + large paired per row)

    private var iconColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            columnHeader("Icon")
            caption("All variants can have an icon on the left.")

            iconRow { compact in
                Button {} label: { iconLabel("Brand", compact: compact) }
                    .buttonStyle(BrandButtonStyle(compact: compact, fullWidth: false))
            }
            iconRow { compact in
                Button {} label: { iconLabel("Default", compact: compact) }
                    .buttonStyle(PrimaryButtonStyle(compact: compact, fullWidth: false))
            }
            iconRow { compact in
                Button {} label: { iconLabel("Secondary", compact: compact) }
                    .buttonStyle(SecondaryFillButtonStyle(compact: compact, fullWidth: false))
            }
            iconRow { compact in
                Button {} label: { iconLabel("Ghost", compact: compact) }
                    .buttonStyle(GhostButtonStyle(compact: compact))
                    .fixedSize(horizontal: true, vertical: false)
            }

            Spacer().frame(height: 16)

            iconRow { compact in
                Button {} label: { iconLabel("Destructive", compact: compact) }
                    .buttonStyle(PrimaryDestructiveButtonStyle(compact: compact, fullWidth: false))
            }
            iconRow { compact in
                Button {} label: { iconLabel("Destructive", compact: compact) }
                    .buttonStyle(SecondaryDestructiveButtonStyle(compact: compact, fullWidth: false))
            }
            iconRow { compact in
                Button {} label: { iconLabel("Destructive", compact: compact) }
                    .buttonStyle(DestructiveGhostButtonStyle(compact: compact))
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    /// Mirrors Figma's leading-icon sizing: 16pt for compact buttons, 24pt for large.
    private func iconLabel(_ text: String, compact: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: compact ? 16 : 24))
            Text(text)
        }
    }

    /// Renders a row of two button samples (compact on the left, large on the right)
    /// so the small/large pair shares a Y baseline like the Figma "Icon" column.
    private func iconRow<Content: View>(@ViewBuilder content: @escaping (_ compact: Bool) -> Content) -> some View {
        HStack(alignment: .top, spacing: 12) {
            content(true)
            content(false)
        }
    }

    // MARK: States column (Pressed + Inactive — both at large size)

    private var statesColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            columnHeader("States")
            HStack(alignment: .top, spacing: 24) {
                statesStack(label: "Pressed", inactive: false)
                statesStack(label: "Inactive\n36% opacity", inactive: true)
            }
        }
    }

    @ViewBuilder
    private func statesStack(label: String, inactive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            caption(label)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button("Pressed") {}
                .buttonStyle(BrandButtonStyle(disabled: inactive, fullWidth: false, pressed: !inactive))
            Button("Pressed") {}
                .buttonStyle(PrimaryButtonStyle(disabled: inactive, fullWidth: false, pressed: !inactive))
            Button("Pressed") {}
                .buttonStyle(SecondaryFillButtonStyle(disabled: inactive, fullWidth: false, pressed: !inactive))
            Button("Pressed") {}
                .buttonStyle(GhostButtonStyle(disabled: inactive, pressed: !inactive))
                .fixedSize(horizontal: true, vertical: false)

            Spacer().frame(height: 16)

            Button("Pressed") {}
                .buttonStyle(PrimaryDestructiveButtonStyle(disabled: inactive, fullWidth: false, pressed: !inactive))
            Button("Pressed") {}
                .buttonStyle(SecondaryDestructiveButtonStyle(disabled: inactive, fullWidth: false, pressed: !inactive))
            Button("Pressed") {}
                .buttonStyle(DestructiveGhostButtonStyle(disabled: inactive, pressed: !inactive))
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}

#Preview("iOS Buttons (Figma) / Light") {
    IOSButtonsDebugView()
        .preferredColorScheme(.light)
}

#Preview("iOS Buttons (Figma) / Dark") {
    IOSButtonsDebugView()
        .preferredColorScheme(.dark)
}

#endif
