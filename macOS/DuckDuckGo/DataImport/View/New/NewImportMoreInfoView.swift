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
            PasswordEntryExampleView()
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
}

// MARK: - Metrics

private extension NewImportMoreInfoView {
    enum Metrics {
        static let itemHeight: CGFloat = 20
        static let largeOuterPadding: CGFloat = 70
        static let imageBottomPadding: CGFloat = 120
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

    final class Coordinator: NSObject {
        var popover: NSPopover?
    }
}
