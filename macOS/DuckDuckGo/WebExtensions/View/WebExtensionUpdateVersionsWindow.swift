//
//  WebExtensionUpdateVersionsWindow.swift
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

import AppKit
import SwiftUI
import WebExtensions

@available(macOS 15.4, *)
@MainActor
private struct WebExtensionUpdateVersionsView: View {
    let manager: WebExtensionManaging

    @State private var installed: [InstalledWebExtension] = []
    @State private var pending: [ChromeWebStoreVerifiedUpdate] = []
    @State private var offeredVersion: String?
    @State private var errorMessage: String?
    @State private var isRefreshing = false
    @State private var isChecking = false
    @State private var refreshedAt: Date?

    private var localFixtureIdentifier: String? {
#if DEBUG
        guard let manager = manager as? WebExtensionManager, ChromeWebStoreManualUpdateTesting().owns(manager) else { return nil }
        return ChromeWebStoreManualUpdateTesting.extensionID
#else
        return nil
#endif
    }

    private var isLocalProfile: Bool { localFixtureIdentifier != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 28, weight: .medium)).foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "Extension Updates").font(.title2.weight(.semibold))
                    Text(verbatim: isLocalProfile ? "Local test profile" : "Chrome Web Store extensions")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isRefreshing || isChecking { ProgressView().controlSize(.small) }
            }
            ScrollView { versionsGrid.padding(16) }
                .background(.background, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
            if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red) }
            Text(verbatim: "Available shows the local server offer, or a verified download. Updates apply at the next launch.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
#if DEBUG
                if isLocalProfile {
                    Button { NSWorkspace.shared.open(ChromeWebStoreManualUpdateTesting.controlPageURL) } label: {
                        Text(verbatim: "Open Local Server")
                    }
                }
#endif
                if let refreshedAt {
                    Text(verbatim: "Updated " + refreshedAt.formatted(date: .omitted, time: .standard))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { Task { await refresh() } } label: { Text(verbatim: "Refresh") }
                    .disabled(isRefreshing || isChecking)
                Button { Task { await checkForUpdates() } } label: { Text(verbatim: "Check for Updates") }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRefreshing || isChecking || manager.chromeWebStore?.canCheckForUpdates != true)
            }
        }
        .padding(24)
        .frame(minWidth: 720, minHeight: 360)
        .task { await refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            guard (notification.object as? NSWindow)?.identifier == WebExtensionUpdateVersionsWindowPresenter.identifier else { return }
            Task { await refresh() }
        }
    }

    private var versionsGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 16) {
            GridRow {
                Text(verbatim: "Extension").frame(maxWidth: .infinity, alignment: .leading)
                Text(verbatim: "Installed")
                Text(verbatim: "Available")
                Text(verbatim: "Status")
            }
            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Divider().gridCellColumns(4)
            ForEach(installed) { extensionInfo in
                let update = pending.first {
                    $0.extensionID == extensionInfo.storeIdentity?.id
                        && ($0.installationIdentifier == nil || $0.installationIdentifier == extensionInfo.uniqueIdentifier)
                }
                let available = isLocalProfile && extensionInfo.storeIdentity?.id == localFixtureIdentifier
                    ? offeredVersion : update?.version
                versionRow(name: extensionInfo.name ?? "Unnamed extension", installedVersion: extensionInfo.version,
                           availableVersion: available, status: update != nil ? "Ready after restart" : (extensionInfo.isDisabled ? "Disabled" : "Installed"),
                           isPending: update != nil)
            }
            if let localFixtureIdentifier, !installed.contains(where: { $0.storeIdentity?.id == localFixtureIdentifier }) {
                versionRow(name: "Extension Update Test", installedVersion: nil, availableVersion: offeredVersion,
                           status: "Not installed", isPending: false)
            } else if installed.isEmpty {
                Text(verbatim: "No Chrome Web Store extensions installed.")
                    .foregroundStyle(.secondary).padding(.vertical, 24).gridCellColumns(4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func versionRow(name: String, installedVersion: String?, availableVersion: String?, status: String, isPending: Bool) -> some View {
        GridRow {
            Text(name).fontWeight(.medium).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            Text(installedVersion ?? "—").monospacedDigit()
            Text(availableVersion ?? "Unknown").monospacedDigit()
            Text(status).font(.caption.weight(.medium))
                .foregroundStyle(isPending ? Color.orange : Color.secondary)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background((isPending ? Color.orange : Color.secondary).opacity(0.12), in: Capsule())
        }
    }

    private func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        installed = manager.webExtensionIdentifiers.compactMap { manager.installedExtension(identifier: $0) }
            .filter { $0.storeIdentity?.store == .chromeWebStore }
            .sorted { ($0.name ?? "").localizedStandardCompare($1.name ?? "") == .orderedAscending }
        errorMessage = nil
        pending = []
        offeredVersion = nil
        do {
            if let service = manager.chromeWebStore as? ChromeWebStoreService {
                pending = try await service.pendingUpdates.allPendingUpdates()
            }
#if DEBUG
            if isLocalProfile {
                offeredVersion = try await ChromeWebStoreManualUpdateTesting().offeredVersion()
            }
#endif
            refreshedAt = Date()
        } catch { errorMessage = "Could not refresh versions: " + error.localizedDescription }
    }

    private func checkForUpdates() async {
        guard let service = manager.chromeWebStore, service.canCheckForUpdates, !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        await service.checkForUpdatesNow()
        await refresh()
    }
}

@available(macOS 15.4, *)
@MainActor
enum WebExtensionUpdateVersionsWindowPresenter {
    static let identifier = NSUserInterfaceItemIdentifier("WebExtensionUpdateVersions")

    static func show(manager: WebExtensionManaging) {
        let window: NSWindow
        if let existing = NSApp.windows.first(where: { $0.identifier == identifier }) {
            window = existing
        } else {
            let controller = VersionsViewController(rootView: WebExtensionUpdateVersionsView(manager: manager))
            window = NSWindow(contentViewController: controller)
            window.identifier = identifier
            window.title = "Extension Updates"
            window.isReleasedWhenClosed = false
            window.styleMask.insert(.resizable)
            window.setContentSize(NSSize(width: 760, height: 400))
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
    }
}

@available(macOS 15.4, *)
private final class VersionsViewController: NSHostingController<WebExtensionUpdateVersionsView> {
    @objc func closeTab(_ sender: Any?) { view.window?.performClose(sender) }
}
