//
//  PIRAssistWindowPresenter.swift
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

#if DEBUG
import AppKit
import DataBrokerProtectionCore
import DesignResourcesKit
import DesignResourcesKitIcons
import SwiftUI
import WebKit

/// Owns one "Removing you from…" window per running assisted job. Closing a window only hides it.
@MainActor
final class PIRAssistWindowPresenter: PIRAssistPresenting {
    private var windows: [PIRAssistItemID: NSWindow] = [:]
    private var closeDelegates: [PIRAssistItemID: HideOnCloseDelegate] = [:]

    func present(_ session: PIRAssistSession) {
        let window = windows[session.id] ?? makeWindow(for: session)
        windows[session.id] = window
        if !window.isVisible {
            window.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func dismiss(_ session: PIRAssistSession) {
        guard let window = windows.removeValue(forKey: session.id) else { return }
        closeDelegates[session.id] = nil
        session.webView.removeFromSuperview()
        window.orderOut(nil)
        window.contentView = nil
    }

    private func makeWindow(for session: PIRAssistSession) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Removing you from \(session.brokerName)"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 960, height: 600)
        let delegate = HideOnCloseDelegate()
        closeDelegates[session.id] = delegate
        window.delegate = delegate

        let content = NSView()
        let bar = NSHostingView(rootView: PIRAssistAddressBar(session: session))
        let panel = NSHostingView(rootView: PIRAssistStepsPanel(session: session, close: { [weak window] in window?.performClose(nil) }))
        let webView = session.webView
        webView.removeFromSuperview()
        for view in [bar, webView, panel] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: content.topAnchor),
            bar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: webView.trailingAnchor),
            webView.topAnchor.constraint(equalTo: bar.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            webView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            panel.leadingAnchor.constraint(equalTo: webView.trailingAnchor),
            panel.topAnchor.constraint(equalTo: content.topAnchor),
            panel.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            panel.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            panel.widthAnchor.constraint(equalToConstant: 380)
        ])
        window.contentView = content
        return window
    }
}

private final class HideOnCloseDelegate: NSObject, NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}

/// Shows where the page is. The address can't be changed.
private struct PIRAssistAddressBar: View {
    @ObservedObject var session: PIRAssistSession
    @State private var host = ""

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: DesignSystemImages.Glyphs.Size16.lock)
                .renderingMode(.template)
                .foregroundColor(Color(designSystemColor: .iconsSecondary))
            Text(host)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(Color(designSystemColor: .surfaceSecondary))
        .onReceive(session.webView.publisher(for: \.url)) { url in
            host = url?.host ?? ""
        }
    }
}
#endif
