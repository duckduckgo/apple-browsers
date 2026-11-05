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

/// Owns one "Removing you from…" window per running assisted job. Closing a window only hides it, until the
/// request is sent: then the window stays on the done screen until the user closes it.
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
        if session.submission != nil, windows[session.id]?.isVisible == true {
            closeDelegates[session.id]?.onClose = { [weak self] in self?.remove(session) }
            return
        }
        remove(session)
    }

    private func remove(_ session: PIRAssistSession) {
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
        let divider = NSHostingView(rootView: Color(designSystemColor: .containerBorderPrimary))
        if #available(macOS 13.0, *) {
            // The window keeps the size the user gave it, whatever the panel shows.
            bar.sizingOptions = []
            panel.sizingOptions = []
        }
        let webView = session.webView
        webView.removeFromSuperview()
        for view in [bar, webView, divider, panel] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: content.topAnchor),
            bar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            bar.heightAnchor.constraint(equalToConstant: 46),
            bar.trailingAnchor.constraint(equalTo: webView.trailingAnchor),
            webView.topAnchor.constraint(equalTo: bar.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            webView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: webView.trailingAnchor),
            divider.topAnchor.constraint(equalTo: content.topAnchor),
            divider.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),
            panel.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
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
    var onClose: (() -> Void)?

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        onClose?()
        return false
    }
}

/// Shows where the page is and whose turn it is. The address can't be changed.
private struct PIRAssistAddressBar: View {
    @ObservedObject var session: PIRAssistSession
    @State private var url: URL?

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: DesignSystemImages.Glyphs.Size16.lock)
                .renderingMode(.template)
                .foregroundColor(Color(designSystemColor: .iconsSecondary))
            (Text(host).foregroundColor(Color(designSystemColor: .textPrimary))
             + Text(path).foregroundColor(Color(designSystemColor: .textSecondary)))
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 16)
            Text(status)
                .font(.system(size: 13))
                .foregroundColor(Color(designSystemColor: .textSecondary))
        }
        .padding(.horizontal, 20)
        .frame(height: 46)
        .background(Color(designSystemColor: .surfaceTertiary))
        .overlay(alignment: .bottom) {
            Color(designSystemColor: .containerBorderPrimary).frame(height: 1)
        }
        // The agent's own placeholder page isn't somewhere the user is.
        .onReceive(session.webView.publisher(for: \.url)) { url = ["http", "https"].contains($0?.scheme) ? $0 : nil }
    }

    private var status: String {
        if session.submission != nil { return "Done" }
        return session.userTurn == nil ? "Filling in" : "Waiting for you"
    }

    private var host: String {
        guard let host = url?.host else { return "" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private var path: String {
        guard let path = url?.path, path.count > 1 else { return "" }
        return " / " + path.dropFirst().replacingOccurrences(of: "/", with: " / ")
    }
}
#endif
