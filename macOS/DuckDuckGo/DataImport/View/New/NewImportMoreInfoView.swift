//
//  NewImportMoreInfoView.swift
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

import Foundation
import SwiftUI
import DesignResourcesKit
import AppKit

struct NewImportMoreInfoView: View {
    @State private var showPopover = false

    var body: some View {
        VStack(alignment: .center) {
            ZStack(alignment: .topLeading) {
                promptImage
                textPlaceholders
                buttonArea
                cursor
            }
            .frame(width: Metrics.containerImageWidth)
            .padding(EdgeInsets(top: Metrics.largeOuterPadding, leading: Metrics.largeOuterPadding, bottom: Metrics.itemHeight, trailing: Metrics.largeOuterPadding))
            .overlay(
                ProgrammaticallyDismissedPopover(
                    isPresented: $showPopover,
                ) {
                    if #available(macOS 12, *), let attr = try? AttributedString(markdown: UserText.importChromeAllowKeychainIntructions) {
                        Text(attr)
                            .padding()
                            .frame(width: 280)
                    } else {
                        Text(UserText.importChromeAllowKeychainIntructions) // fallback
                            .padding()
                            .frame(width: 280)
                    }
                }
            )
        }
        .padding(.bottom, Metrics.imageBottomPadding)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showPopover = true
            }
        }
    }

    private var promptImage: some View {
        Image(.importKeychainPromptContainer)
    }

    private var textPlaceholders: some View {
        VStack(alignment: .leading, spacing: 12) {
            textPlaceholder(width: 244)
            textPlaceholder(width: 183)
        }
        .padding(.top, 28)
        .padding(.leading, 104)
    }

    private var buttonArea: some View {
        HStack(spacing: Metrics.spacing) {
            placeholderButton
            allowButton
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .padding(.trailing, Metrics.spacing * 2)
        .padding(.bottom, 35)
    }

    private var cursor: some View {
        Image(.chromiumImportCursor)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, 0)
            .padding(.bottom, 0)
    }

    private var placeholderButton: some View {
        placeholderRect(width: 80, cornerRadius: Metrics.buttonCornerRadius)
    }

    private var allowButton: some View {
        Text(UserText.importChromeAllowButtonTitle)
            .padding(.horizontal, Metrics.spacing)
            .frame(height: Metrics.itemHeight)
            .background(
                placeholderRect(cornerRadius: Metrics.buttonCornerRadius)
            )
    }

    private func textPlaceholder(width: CGFloat) -> some View {
        placeholderRect(width: width, cornerRadius: Metrics.itemHeight / 2.0)
    }

    private func placeholderRect(width: CGFloat? = nil, cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color(designSystemColor: .containerFillTertiary))
            .frame(width: width, height: Metrics.itemHeight)
    }
}

// MARK: - Metrics

private extension NewImportMoreInfoView {
    enum Metrics {
        static let itemHeight: CGFloat = 20
        static let largeOuterPadding: CGFloat = 70
        static let imageBottomPadding: CGFloat = 120
        static let spacing: CGFloat = 16
        static let buttonCornerRadius: CGFloat = 5
        static let containerImageWidth: CGFloat = 380
        static let popoverContentWidth: CGFloat = 280
    }
}

#Preview {
    NewImportMoreInfoView()
}

/// A popover that can be dismissed programmatically, so we can prevent it from being dismissed by clicking outside of it.
/// (This can't be done with a SwiftUI popover directly)
///
private struct ProgrammaticallyDismissedPopover<Content: View>: NSViewRepresentable {
    @Binding var isPresented: Bool
    let content: () -> Content

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if isPresented {
            if context.coordinator.popover == nil {
                let hostingController = NSHostingController(rootView: content())
                hostingController.view.frame = CGRect(origin: .zero, size: hostingController.view.intrinsicContentSize)
                
                let popover = NSPopover()
                popover.contentViewController = hostingController
                popover.behavior = .applicationDefined
                popover.animates = true
                
                context.coordinator.popover = popover
                popover.show(relativeTo: nsView.bounds, of: nsView, preferredEdge: .minY)
            }
        } else {
            context.coordinator.popover?.close()
            context.coordinator.popover = nil
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject {
        var popover: NSPopover?
    }
}
