//
//  AboutPanel.swift
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

import SwiftUI
import AppKit
import BrowserServicesKit
import Common

// SwiftUI view for the About panel
struct AboutPanelView: View {

    let isInternal: Bool

    private var appName: String {
#if APPSTORE
        UserText.duckDuckGoForMacAppStore
#else
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? ""
#endif
    }
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }
    private var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    }
    private var copyright: String {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? ""
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
                .cornerRadius(16)

            Text(appName)
                .font(.title3)

            HStack(spacing: 8) {
                Text(UserText.versionLabel(version: appVersion, build: appBuild))
                    .font(.footnote)
                    .onTapGesture {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(
                            AppVersion.shared.versionAndBuildNumber,
                            forType: .string
                        )
                    }
                    .cursor(.pointingHand)
                    .help(UserText.clickToCopyVersion)
                if isInternal {
                    Text("BETA")
                        .font(.footnote)
                        .fontWeight(.bold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.betaLabelBackground)
                        )
                        .foregroundColor(Color.betaLabelForeground)
                }
            }

            Text(copyright)
                .font(.footnote)
                .multilineTextAlignment(.center)
        }
        .padding([.horizontal, .bottom], 20)
        .padding(.top, 10)
        .frame(minWidth: 280)
    }
}

// Controller to display the About panel
@MainActor
final class AboutPanelController {

    private var panel: AboutPanelWindow

    private init(internalUserDecider: InternalUserDecider) {
        panel = AboutPanelWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.center()

        let hosting = NSHostingController(rootView: AboutPanelView(isInternal: internalUserDecider.isInternalUser))
        panel.contentView = hosting.view
    }

    private func showPanel() {
        panel.show()
    }

    static func show(internalUserDecider: InternalUserDecider) {
        guard let panel = NSApp.windows.first(where: { $0 is AboutPanelWindow }) as? AboutPanelWindow else {
            let aboutController = AboutPanelController(internalUserDecider: internalUserDecider)
            aboutController.showPanel()
            return
        }
        panel.show()
    }
}

// A custom panel that closes when the user presses Escape.
private class AboutPanelWindow: NSPanel {
    override func cancelOperation(_ sender: Any?) {
        self.close()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              let chars = event.charactersIgnoringModifiers?.lowercased(),
              chars == "w",
              event.modifierFlags.contains(.command) else {
            return super.performKeyEquivalent(with: event)
        }
        self.close()
        return true
    }

    func show() {
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
