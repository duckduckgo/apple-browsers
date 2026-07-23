//
//  PromptBarShortcutRecorderView.swift
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

import Carbon.HIToolbox
import DesignResourcesKit
import DesignResourcesKitIcons
import PreferencesUI_macOS
import SwiftUI
import SwiftUIExtensions

/// Records the Prompt Bar keyboard shortcut. Shows the current combo as keycaps;
/// clicking arms a local key monitor ("Type shortcut", Esc cancels). Combos reserved
/// by the system are rejected with an inline error instead of being saved.
struct PromptBarShortcutRecorderView: View {

    @Binding var shortcut: PromptBarShortcut

    @Environment(\.isEnabled) private var isEnabled

    private enum RecorderState: Equatable {
        case idle
        case recording
        case rejected(PromptBarShortcut, ownerName: String)
    }

    @State private var state: RecorderState = .idle
    @State private var keyDownMonitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Button(action: toggleRecording) {
                    recorderWell
                }
                .buttonStyle(.plain)
                .cursor(.pointingHand)
                .accessibilityIdentifier("Preferences.AIChat.promptBarShortcutRecorder")

                if showsResetToDefault {
                    TextButton(UserText.promptBarShortcutResetToDefault) {
                        stopRecording(transitioningTo: .idle)
                        shortcut = .defaultShortcut
                    }
                    .accessibilityIdentifier("Preferences.AIChat.promptBarShortcutResetToDefault")
                }
            }

            if state == .recording {
                TextMenuItemCaption(UserText.promptBarShortcutRecordingCancelHint)
            }

            if case .rejected(let rejectedShortcut, let ownerName) = state {
                errorBox(for: rejectedShortcut, ownerName: ownerName)
            }
        }
        .opacity(isEnabled ? 1 : 0.5)
        .onChange(of: isEnabled) { enabled in
            if !enabled {
                stopRecording(transitioningTo: .idle)
            }
        }
        .onDisappear {
            stopRecording(transitioningTo: .idle)
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var recorderWell: some View {
        Group {
            if state == .recording {
                Text(UserText.promptBarShortcutRecordingPlaceholder)
                    .font(.system(size: 13))
                    .foregroundColor(Color(designSystemColor: .accentPrimary))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            } else {
                HStack(spacing: 4) {
                    ForEach(Array(keyCapLabels.enumerated()), id: \.offset) { _, label in
                        KeyCapChip(label: label)
                    }
                }
                .padding(4)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(wellBorderColor, lineWidth: state == .idle ? 1 : 2)
        )
    }

    private func errorBox(for rejectedShortcut: PromptBarShortcut, ownerName: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(nsImage: DesignSystemImages.Glyphs.Size16.exclamationRecolorable)
                .renderingMode(.template)
            Text(UserText.promptBarShortcutReservedError(shortcut: rejectedShortcut.displayString, ownerName: ownerName))
                .font(.system(size: 12))
                .fixMultilineScrollableText()
        }
        .foregroundColor(Color(designSystemColor: .destructivePrimary))
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(designSystemColor: .destructiveTertiary))
        )
    }

    private struct KeyCapChip: View {
        let label: String

        var body: some View {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .frame(minWidth: 16)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(designSystemColor: .surfacePrimary))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color(designSystemColor: .lines))
                )
        }
    }

    // MARK: - Display state

    /// While a combo is rejected the well keeps showing it alongside the error,
    /// so the user can see what they typed; the saved shortcut is unchanged.
    private var displayedShortcut: PromptBarShortcut {
        if case .rejected(let rejectedShortcut, _) = state {
            return rejectedShortcut
        }
        return shortcut
    }

    private var keyCapLabels: [String] {
        displayedShortcut.modifierSymbols + [displayedShortcut.keyDisplayString]
    }

    private var wellBorderColor: Color {
        switch state {
        case .idle: return Color(designSystemColor: .lines)
        case .recording: return Color(designSystemColor: .accentPrimary)
        case .rejected: return Color(designSystemColor: .destructivePrimary)
        }
    }

    private var showsResetToDefault: Bool {
        switch state {
        case .recording: return false
        case .rejected: return true
        case .idle: return shortcut != .defaultShortcut
        }
    }

    // MARK: - Recording

    private func toggleRecording() {
        if case .recording = state {
            stopRecording(transitioningTo: .idle)
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        state = .recording
        guard keyDownMonitor == nil else { return }
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
        }
    }

    private func stopRecording(transitioningTo newState: RecorderState) {
        if let monitor = keyDownMonitor {
            NSEvent.removeMonitor(monitor)
            keyDownMonitor = nil
        }
        state = newState
    }

    /// Swallows key events while recording: bare Esc cancels, combos without a
    /// required modifier are ignored, reserved combos surface the inline error.
    private func handle(_ event: NSEvent) -> NSEvent? {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if event.keyCode == UInt16(kVK_Escape), modifiers.isEmpty {
            stopRecording(transitioningTo: .idle)
            return nil
        }

        guard let candidate = PromptBarShortcut(event: event), candidate.hasRequiredModifiers else {
            return nil
        }

        if let ownerName = candidate.reservedSystemOwnerName {
            stopRecording(transitioningTo: .rejected(candidate, ownerName: ownerName))
        } else {
            shortcut = candidate
            stopRecording(transitioningTo: .idle)
        }
        return nil
    }
}
