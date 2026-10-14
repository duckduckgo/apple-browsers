//
//  AIChatScreenshotSourcePicker.swift
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

import AIChat
import AppKit
import os.log
import ScreenCaptureKit
import SwiftUI

/// Select Window or Display through our own picker (the Windows approach). Listing windows needs
/// Screen Recording, unlike the system picker.
@MainActor
final class AIChatScreenshotSourcePicker: NSObject, NSWindowDelegate {

    enum Outcome {
        case captured(image: CGImage, kind: AIChatScreenshotKind)
        case cancelled
        case failed(AIChatScreenshotFailureReason)
    }

    private let model: AIChatScreenshotSourcePickerModel
    private var panel: NSPanel?
    private var continuation: CheckedContinuation<AIChatScreenshotSourcePickerModel.Finish, Never>?

    init(excludingWindowIDs windowIDs: [CGWindowID]) {
        model = AIChatScreenshotSourcePickerModel(excludedWindowIDs: Set(windowIDs))
    }

    func capture() async -> Outcome {
        let finish = await withCheckedContinuation { continuation in
            self.continuation = continuation
            model.onFinish = { [weak self] in self?.finish($0) }
            present()
        }

        switch finish {
        case .cancelled:
            return .cancelled
        case .failed:
            return .failed(.unavailable)
        case .picked(let source):
            // ponytail: fixed wait so the closed picker is off screen; refetch content if it still shows up.
            if source.kind == .screen {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            do {
                let image = try await AIChatScreenshotSourcePickerModel.image(of: source, maxPixels: nil)
                return .captured(image: image, kind: source.kind)
            } catch {
                let error = error as NSError
                Logger.aiChat.error("Duck.ai screenshot capture failed: \(error.domain, privacy: .public) \(error.code, privacy: .public)")
                return .failed(.failed)
            }
        }
    }

    private func present() {
        let hostingController = NSHostingController(rootView: AIChatScreenshotSourcePickerView(model: model))

        // Non-activating so it takes key over the prompt bar without activating the app.
        let panel = NSPanel(contentRect: .zero, styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = UserText.aiChatScreenshotPickerTitle
        panel.contentViewController = hostingController
        panel.setContentSize(hostingController.view.fittingSize)
        panel.level = .modalPanel
        panel.hidesOnDeactivate = false
        panel.sharingType = .none
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel

        // Loaded once the panel is on screen, so the Entire Screen preview can leave it out.
        model.excludedWindowIDs.insert(CGWindowID(panel.windowNumber))
        Task { await model.load() }
    }

    private func finish(_ finish: AIChatScreenshotSourcePickerModel.Finish) {
        guard let continuation else { return }
        self.continuation = nil
        panel?.delegate = nil
        panel?.close()
        panel = nil
        continuation.resume(returning: finish)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        panel = nil
        finish(.cancelled)
    }
}

struct AIChatScreenshotSource: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let icon: NSImage?
    let kind: AIChatScreenshotKind
    let filter: SCContentFilter
    let pixelSize: CGSize
}

@MainActor
final class AIChatScreenshotSourcePickerModel: ObservableObject {

    enum Tab: Hashable {
        case window
        case screen
    }

    enum Finish {
        case picked(AIChatScreenshotSource)
        case cancelled
        case failed
    }

    static let previewMaxPixels: CGFloat = 960

    @Published var tab: Tab = .window {
        didSet { if tab != oldValue { selectedID = nil } }
    }
    @Published var selectedID: AIChatScreenshotSource.ID? {
        didSet { if selectedID != oldValue { updatePreview() } }
    }
    @Published private(set) var windows: [AIChatScreenshotSource] = []
    @Published private(set) var screens: [AIChatScreenshotSource] = []
    @Published private(set) var isLoading = true
    @Published private(set) var preview: CGImage?

    var excludedWindowIDs: Set<CGWindowID>
    var onFinish: ((Finish) -> Void)?
    private var previewTask: Task<Void, Never>?

    init(excludedWindowIDs: Set<CGWindowID>) {
        self.excludedWindowIDs = excludedWindowIDs
    }

    var sources: [AIChatScreenshotSource] {
        tab == .window ? windows : screens
    }

    var selected: AIChatScreenshotSource? {
        sources.first { $0.id == selectedID }
    }

    func load() async {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        } catch {
            let error = error as NSError
            Logger.aiChat.error("Duck.ai screenshot picker failed to list content: \(error.domain, privacy: .public) \(error.code, privacy: .public)")
            onFinish?(.failed)
            return
        }

        windows = Self.windowSources(from: content.windows, excluding: excludedWindowIDs)
        let excludedWindows = content.windows.filter { excludedWindowIDs.contains($0.windowID) }
        screens = content.displays.enumerated().map { index, display in
            Self.screenSource(for: display, index: index, excluding: excludedWindows)
        }
        isLoading = false
    }

    func share(_ id: AIChatScreenshotSource.ID? = nil) {
        guard let source = sources.first(where: { $0.id == (id ?? selectedID) }) else { return }
        previewTask?.cancel()
        onFinish?(.picked(source))
    }

    func cancel() {
        previewTask?.cancel()
        onFinish?(.cancelled)
    }

    /// `nil` keeps full size.
    static func image(of source: AIChatScreenshotSource, maxPixels: CGFloat?) async throws -> CGImage {
        var size = source.pixelSize
        if let maxPixels, max(size.width, size.height) > maxPixels {
            let scale = maxPixels / max(size.width, size.height)
            size = CGSize(width: size.width * scale, height: size.height * scale)
        }
        return try await AIChatScreenshotStill.capture(source.filter, width: max(1, Int(size.width)), height: max(1, Int(size.height)))
    }

    private func updatePreview() {
        previewTask?.cancel()
        preview = nil
        guard let source = selected else { return }

        previewTask = Task { [weak self] in
            let image = try? await Self.image(of: source, maxPixels: Self.previewMaxPixels)
            guard !Task.isCancelled else { return }
            self?.preview = image
        }
    }

    /// Normal-level, titled windows other than ours, front to back.
    private static func windowSources(from windows: [SCWindow], excluding excludedIDs: Set<CGWindowID>) -> [AIChatScreenshotSource] {
        let frontToBack = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? [])
            .compactMap { $0[kCGWindowNumber as String] as? CGWindowID }
        let order = Dictionary(frontToBack.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        // ponytail: the largest backing scale for every window; a non-Retina window on a mixed setup is captured at 2x, harmless after the 1024 px downscale.
        let scale = NSScreen.screens.map(\.backingScaleFactor).max() ?? 2

        return windows
            .filter { window in
                window.windowLayer == 0
                    && window.isOnScreen
                    && !(window.title ?? "").isEmpty
                    && window.frame.width >= 50 && window.frame.height >= 50
                    && window.owningApplication != nil
                    && !excludedIDs.contains(window.windowID)
            }
            .sorted { (order[$0.windowID] ?? .max) < (order[$1.windowID] ?? .max) }
            .map { window in
                let app = window.owningApplication
                return AIChatScreenshotSource(id: "window-\(window.windowID)",
                                              title: window.title ?? "",
                                              subtitle: app?.applicationName,
                                              icon: app.flatMap { NSRunningApplication(processIdentifier: $0.processID)?.icon },
                                              kind: .window,
                                              filter: SCContentFilter(desktopIndependentWindow: window),
                                              pixelSize: CGSize(width: window.frame.width * scale, height: window.frame.height * scale))
            }
    }

    private static func screenSource(for display: SCDisplay, index: Int, excluding excludedWindows: [SCWindow]) -> AIChatScreenshotSource {
        let screen = NSScreen.screens.first { $0.displayID == display.displayID }
        let scale = screen?.backingScaleFactor ?? 2
        return AIChatScreenshotSource(id: "screen-\(display.displayID)",
                                      title: screen?.localizedName ?? "\(UserText.aiChatScreenshotPickerScreenTab) \(index + 1)",
                                      subtitle: "\(display.width) × \(display.height)",
                                      icon: nil,
                                      kind: .screen,
                                      filter: SCContentFilter(display: display, excludingWindows: excludedWindows),
                                      pixelSize: CGSize(width: CGFloat(display.width) * scale, height: CGFloat(display.height) * scale))
    }
}

struct AIChatScreenshotSourcePickerView: View {

    @ObservedObject var model: AIChatScreenshotSourcePickerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(UserText.aiChatScreenshotPickerSubtitle)
                .foregroundColor(.secondary)

            Picker("" as String, selection: $model.tab) {
                Text(UserText.aiChatScreenshotPickerWindowTab).tag(AIChatScreenshotSourcePickerModel.Tab.window)
                Text(UserText.aiChatScreenshotPickerScreenTab).tag(AIChatScreenshotSourcePickerModel.Tab.screen)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack(spacing: 12) {
                sourceList
                    .frame(width: 260)
                preview
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: 300)

            HStack {
                Spacer()
                Button(UserText.cancel) { model.cancel() }
                    .keyboardShortcut(.cancelAction)
                Button(UserText.aiChatScreenshotPickerShare) { model.share() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.selected == nil)
            }
        }
        .padding(20)
        .frame(width: 640)
    }

    @ViewBuilder
    private var sourceList: some View {
        if model.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let list = List(model.sources, selection: $model.selectedID) { source in
                row(for: source)
            }
            if #available(macOS 13.0, *) {
                // Double-click or Return shares the row.
                list.contextMenu(forSelectionType: AIChatScreenshotSource.ID.self, menu: { _ in EmptyView() }, primaryAction: { ids in
                    model.share(ids.first)
                })
            } else {
                list
            }
        }
    }

    private func row(for source: AIChatScreenshotSource) -> some View {
        HStack(spacing: 8) {
            if let icon = source.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "display")
                    .frame(width: 16, height: 16)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(source.title)
                    .lineLimit(1)
                if let subtitle = source.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
            if let preview = model.preview {
                Image(decorative: preview, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(8)
            } else if model.selected != nil {
                ProgressView()
            } else {
                Text(model.tab == .window ? UserText.aiChatScreenshotPickerSelectWindow : UserText.aiChatScreenshotPickerSelectScreen)
                    .foregroundColor(.secondary)
            }
        }
    }
}
