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

/// Select Window or Display through our own picker, laid out like Windows'. Listing windows needs
/// Screen Recording.
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
        let panel = NSPanel(contentRect: .zero, styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = UserText.aiChatScreenshotSelectWindowOrDisplay
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].forEach { panel.standardWindowButton($0)?.isHidden = true }
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

    /// Twice the 200 pt tile, for Retina.
    static let thumbnailMaxPixels: CGFloat = 400

    @Published var tab: Tab = .window {
        didSet { if tab != oldValue { selectedID = nil } }
    }
    @Published var selectedID: AIChatScreenshotSource.ID?
    @Published private(set) var windows: [AIChatScreenshotSource] = []
    @Published private(set) var screens: [AIChatScreenshotSource] = []
    /// A `nil` value is a thumbnail that failed; a missing key is one still loading.
    @Published private(set) var thumbnails: [AIChatScreenshotSource.ID: CGImage?] = [:]
    @Published private(set) var isLoading = true

    var excludedWindowIDs: Set<CGWindowID>
    var onFinish: ((Finish) -> Void)?
    private var thumbnailTask: Task<Void, Never>?

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
        screens = content.displays.map { Self.screenSource(for: $0, excluding: excludedWindows) }
        isLoading = false
        loadThumbnails()
    }

    func share(_ id: AIChatScreenshotSource.ID? = nil) {
        guard let source = sources.first(where: { $0.id == (id ?? selectedID) }) else { return }
        thumbnailTask?.cancel()
        onFinish?(.picked(source))
    }

    func cancel() {
        thumbnailTask?.cancel()
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

    /// ponytail: one at a time, windows first, front to back; a task group if the grid fills in too slowly.
    private func loadThumbnails() {
        let sources = windows + screens
        thumbnailTask = Task { [weak self] in
            for source in sources {
                guard !Task.isCancelled else { return }
                let image = try? await Self.image(of: source, maxPixels: Self.thumbnailMaxPixels)
                self?.thumbnails.updateValue(image, forKey: source.id)
            }
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

    private static func screenSource(for display: SCDisplay, excluding excludedWindows: [SCWindow]) -> AIChatScreenshotSource {
        let screen = NSScreen.screens.first { $0.displayID == display.displayID }
        let scale = screen?.backingScaleFactor ?? 2
        return AIChatScreenshotSource(id: "screen-\(display.displayID)",
                                      title: screen?.localizedName ?? "\(display.width) × \(display.height)",
                                      subtitle: nil,
                                      icon: nil,
                                      kind: .screen,
                                      filter: SCContentFilter(display: display, excludingWindows: excludedWindows),
                                      pixelSize: CGSize(width: CGFloat(display.width) * scale, height: CGFloat(display.height) * scale))
    }
}

/// Modelled on the Windows picker: tabs, a grid of thumbnails, Capture and Cancel.
struct AIChatScreenshotSourcePickerView: View {

    static let tileSize = CGSize(width: 200, height: 125)

    @ObservedObject var model: AIChatScreenshotSourcePickerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(UserText.aiChatScreenshotSelectWindowOrDisplay)
                .font(.title2.weight(.semibold))
                .padding(.bottom, 16)

            HStack(spacing: 20) {
                tabButton(.window, title: UserText.aiChatScreenshotPickerWindowsTab)
                tabButton(.screen, title: UserText.aiChatScreenshotPickerDisplaysTab)
            }
            Divider()

            grid
                .frame(height: 360)

            Divider()
            HStack {
                Spacer()
                Button(UserText.cancel) { model.cancel() }
                    .keyboardShortcut(.cancelAction)
                Button(UserText.aiChatScreenshotPickerCapture) { model.share() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.selected == nil)
            }
            .padding(.top, 16)
        }
        .padding(20)
        .frame(width: 720)
    }

    private func tabButton(_ tab: AIChatScreenshotSourcePickerModel.Tab, title: String) -> some View {
        let isSelected = model.tab == tab
        return Button {
            model.tab = tab
        } label: {
            Text(title)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? .primary : .secondary)
                .padding(.bottom, 8)
                .overlay(Rectangle().fill(isSelected ? Color.accentColor : Color.clear).frame(height: 2), alignment: .bottom)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var grid: some View {
        if model.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.tileSize.width), spacing: 16, alignment: .topLeading)], alignment: .leading, spacing: 16) {
                    ForEach(model.sources) { source in
                        tile(for: source)
                    }
                }
                .padding(.vertical, 16)
            }
        }
    }

    private func tile(for source: AIChatScreenshotSource) -> some View {
        let isSelected = model.selectedID == source.id
        return VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .quaternaryLabelColor))
                if let thumbnail = model.thumbnails[source.id] {
                    if let thumbnail {
                        Image(decorative: thumbnail, scale: 1)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(6)
                    }
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .frame(width: Self.tileSize.width, height: Self.tileSize.height)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 3))

            HStack(spacing: 6) {
                icon(for: source)
                Text(source.title)
                    .lineLimit(1)
            }
            .frame(width: Self.tileSize.width, alignment: .leading)
        }
        .contentShape(Rectangle())
        .help(source.subtitle.map { "\($0) — \(source.title)" } ?? source.title)
        // The first click selects right away; the second click of a double-click captures.
        .gesture(TapGesture(count: 2).onEnded { model.share(source.id) })
        .simultaneousGesture(TapGesture().onEnded { model.selectedID = source.id })
    }

    @ViewBuilder
    private func icon(for source: AIChatScreenshotSource) -> some View {
        if let icon = source.icon {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 16, height: 16)
        } else {
            Image(systemName: "display")
                .frame(width: 16, height: 16)
        }
    }
}
