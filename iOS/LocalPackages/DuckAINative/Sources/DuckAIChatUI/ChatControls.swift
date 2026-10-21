//
//  ChatControls.swift
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
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct ChatGhostButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(DuckAIChatTokens.Color.textSecondary)
            .background(configuration.isPressed ? DuckAIChatTokens.Color.controlSecondary : .clear, in: Capsule())
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Capsule())
    }
}

struct ChatIconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    var size: CGFloat = 36

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16))
                .frame(width: 16, height: 16)
                .frame(width: size, height: size)
        }
        .buttonStyle(ChatGhostButtonStyle())
        .accessibilityLabel(label)
    }
}

struct ChatCopyButton: View {
    let text: String
    var size: CGFloat = 36
    @State private var isCopied = false
    @State private var resetTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ChatIconButton(symbol: isCopied ? "checkmark" : "square.on.square", label: isCopied ? "Copied" : "Copy", action: {
#if canImport(UIKit)
            UIPasteboard.general.string = text
#elseif canImport(AppKit)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
#endif
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { isCopied = true }
            resetTask?.cancel()
            resetTask = Task { @MainActor in
                do {
                    try await Task.sleep(for: .seconds(2))
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { isCopied = false }
                } catch { }
            }
        }, size: size)
        .contentTransition(.opacity)
        .onDisappear { resetTask?.cancel() }
    }
}

struct AssistantHeading: View {
    let title: String
    var isActive = true
    var isLoading = false
    var isError = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isError ? "exclamationmark.circle.fill" : "sparkles")
                .font(.system(size: 16))
                .foregroundStyle(iconColor)
                .frame(width: 16, height: 16)
                .symbolEffect(.pulse, options: .repeating, isActive: isLoading && !reduceMotion)
            if isLoading && !reduceMotion {
                TimelineView(.animation) { context in
                    let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2) / 2
                    headingText.foregroundStyle(
                        LinearGradient(stops: [
                            .init(color: DuckAIChatTokens.Color.textPrimary, location: 0),
                            .init(color: DuckAIChatTokens.Color.textPrimary, location: 0.3),
                            .init(color: DuckAIChatTokens.Color.textSecondary, location: 0.5),
                            .init(color: DuckAIChatTokens.Color.textPrimary, location: 0.7),
                            .init(color: DuckAIChatTokens.Color.textPrimary, location: 1)
                        ], startPoint: UnitPoint(x: phase * 2 - 1, y: 0.5), endPoint: UnitPoint(x: phase * 2, y: 0.5))
                    )
                }
            } else {
                headingText.foregroundStyle(isError ? DuckAIChatTokens.Color.destructive :
                                            isActive ? DuckAIChatTokens.Color.textPrimary : DuckAIChatTokens.Color.textSecondary)
            }
        }
        .frame(height: 36)
    }

    private var headingText: some View {
        Text(title)
            .font(DuckAIChatTokens.Typography.modelName.font)
            .lineSpacing(DuckAIChatTokens.Typography.modelName.lineSpacing)
    }

    private var iconColor: Color {
        if isError { return DuckAIChatTokens.Color.destructive }
        return isActive ? DuckAIChatTokens.Color.modelIconActive : DuckAIChatTokens.Color.modelIconPrevious
    }
}
