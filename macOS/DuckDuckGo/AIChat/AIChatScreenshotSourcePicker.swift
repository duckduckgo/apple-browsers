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
import DesignResourcesKitIcons
import os.log
import ScreenCaptureKit
import SwiftUI

/// Select Window or Display through our own picker. Listing windows needs Screen Recording.
@MainActor
final class AIChatScreenshotSourcePicker: NSObject, NSWindowDelegate {

    enum Outcome {
        case captured(image: CGImage, kind: AIChatScreenshotKind)
        case cancelled
        case failed(AIChatScreenshotFailureReason)
    }

    private let model: AIChatScreenshotSourcePickerModel
    private let sheetParent: NSWindow?
    private var panel: NSPanel?
    private var continuation: CheckedContinuation<AIChatScreenshotSourcePickerModel.Finish, Never>?

    /// - Parameter sheetParent: the browser window the picker is a sheet on; `nil` floats it over every app.
    init(excludingWindowIDs windowIDs: [CGWindowID], sheetParent: NSWindow?) {
        model = AIChatScreenshotSourcePickerModel(excludedWindowIDs: Set(windowIDs))
        self.sheetParent = sheetParent
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

        // Floating, it's non-activating so it takes key over the prompt bar without activating the app.
        let styleMask: NSWindow.StyleMask = sheetParent == nil ? [.titled, .fullSizeContentView, .nonactivatingPanel] : [.titled, .fullSizeContentView]
        let panel = AIChatScreenshotSourcePickerPanel(contentRect: .zero, styleMask: styleMask, backing: .buffered, defer: false)
        panel.onMoveSelection = { [weak model] in model?.moveSelection(by: $0) }
        panel.title = UserText.aiChatScreenshotSelectWindowOrDisplay
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].forEach { panel.standardWindowButton($0)?.isHidden = true }
        panel.contentViewController = hostingController
        panel.setContentSize(hostingController.view.fittingSize)
        panel.sharingType = .none
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        if let sheetParent {
            sheetParent.beginSheet(panel)
        } else {
            panel.level = .modalPanel
            panel.hidesOnDeactivate = false
            panel.center()
            panel.makeKeyAndOrderFront(nil)
        }
        self.panel = panel

        // Loaded once the panel is on screen, so the Entire Screen preview can leave it out.
        model.excludedWindowIDs.insert(CGWindowID(panel.windowNumber))
        model.startRefreshing()
    }

    func cancel() {
        finish(.cancelled)
    }

    private func finish(_ finish: AIChatScreenshotSourcePickerModel.Finish) {
        guard let continuation else { return }
        self.continuation = nil
        model.stopRefreshing()
        panel?.delegate = nil
        if let panel, let parent = panel.sheetParent {
            parent.endSheet(panel)
        }
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

/// Arrow keys move the selection; Return and Esc reach the buttons through their shortcuts.
private final class AIChatScreenshotSourcePickerPanel: NSPanel {

    var onMoveSelection: ((Int) -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.specialKey {
        case .leftArrow: onMoveSelection?(-1)
        case .rightArrow: onMoveSelection?(1)
        case .upArrow: onMoveSelection?(-AIChatScreenshotSourcePickerView.columnCount)
        case .downArrow: onMoveSelection?(AIChatScreenshotSourcePickerView.columnCount)
        default: super.keyDown(with: event)
        }
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

    /// About twice the tile, for Retina.
    static let thumbnailMaxPixels: CGFloat = 400
    /// ponytail: polls, since macOS has no live thumbnails and no notice when another app's window changes;
    /// a shorter interval costs a capture of every tile each time.
    static let refreshInterval: UInt64 = 2_000_000_000

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
    private var refreshTask: Task<Void, Never>?

    init(excludedWindowIDs: Set<CGWindowID>) {
        self.excludedWindowIDs = excludedWindowIDs
    }

    var sources: [AIChatScreenshotSource] {
        tab == .window ? windows : screens
    }

    var selected: AIChatScreenshotSource? {
        sources.first { $0.id == selectedID }
    }

    /// Lists windows and displays and takes their thumbnails, then again every `refreshInterval`
    /// until `stopRefreshing()`, so closed windows leave and changed ones show what they look like now.
    func startRefreshing() {
        refreshTask = Task { [weak self] in
            while let model = self, !Task.isCancelled {
                do {
                    try await model.refresh()
                } catch {
                    let error = error as NSError
                    Logger.aiChat.error("Duck.ai screenshot picker failed to list content: \(error.domain, privacy: .public) \(error.code, privacy: .public)")
                    // Only a picker that never listed anything ends; a later failure keeps the last list.
                    if model.isLoading { model.onFinish?(.failed) }
                    return
                }
                try? await Task.sleep(nanoseconds: Self.refreshInterval)
            }
        }
    }

    func stopRefreshing() {
        refreshTask?.cancel()
    }

    /// Each thumbnail stays until its replacement is taken, so tiles don't flash empty.
    private func refresh() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)

        windows = Self.windowSources(from: content.windows, excluding: excludedWindowIDs)
        let excludedWindows = content.windows.filter { excludedWindowIDs.contains($0.windowID) }
        screens = content.displays.map { Self.screenSource(for: $0, excluding: excludedWindows) }
        isLoading = false

        // ponytail: one at a time, windows first, front to back; a task group if the grid fills in too slowly.
        let sources = windows + screens
        let ids = Set(sources.map(\.id))
        thumbnails = thumbnails.filter { ids.contains($0.key) }
        if let selectedID, !ids.contains(selectedID) {
            self.selectedID = nil
        }
        for source in sources {
            guard !Task.isCancelled else { return }
            let image = try? await Self.image(of: source, maxPixels: Self.thumbnailMaxPixels)
            thumbnails.updateValue(image, forKey: source.id)
        }
    }

    func share(_ id: AIChatScreenshotSource.ID? = nil) {
        guard let source = sources.first(where: { $0.id == (id ?? selectedID) }) else { return }
        onFinish?(.picked(source))
    }

    func cancel() {
        onFinish?(.cancelled)
    }

    /// Selects the first tile when nothing is selected yet; stops at either end.
    func moveSelection(by offset: Int) {
        guard let index = sources.firstIndex(where: { $0.id == selectedID }) else {
            selectedID = sources.first?.id
            return
        }
        selectedID = sources[min(max(index + offset, 0), sources.count - 1)].id
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

/// A native-looking sheet: a sidebar for windows and displays, a grid of thumbnails, Capture and Cancel.
struct AIChatScreenshotSourcePickerView: View {

    static let thumbnailHeight: CGFloat = 128
    /// Arrow keys move up and down by it.
    static let columnCount = 3

    @ObservedObject var model: AIChatScreenshotSourcePickerModel

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                Text(model.tab == .window ? UserText.aiChatScreenshotPickerSelectWindow : UserText.aiChatScreenshotPickerSelectDisplay)
                    .font(.title.weight(.bold))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .bottomLeading)

                grid
                    // Two rows of tiles.
                    .frame(height: 362)

                Divider()
                HStack(spacing: 10) {
                    Spacer()
                    Button(UserText.cancel) { model.cancel() }
                        .keyboardShortcut(.cancelAction)
                    Button(UserText.aiChatScreenshotPickerCapture) { model.share() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(model.selected == nil)
                }
                .padding(.horizontal, 20)
                .frame(height: 64)
            }
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .frame(width: 800)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            sidebarItem(.window, title: UserText.aiChatScreenshotPickerWindowsTab, icon: DesignSystemImages.Glyphs.Size16.window)
            sidebarItem(.screen, title: UserText.aiChatScreenshotPickerDisplaysTab, icon: DesignSystemImages.Glyphs.Size16.deviceDesktop)
            Spacer(minLength: 0)
        }
        .padding(.top, 32)
        .padding(.horizontal, 10)
        .frame(width: 160)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func sidebarItem(_ tab: AIChatScreenshotSourcePickerModel.Tab, title: String, icon: NSImage) -> some View {
        let isSelected = model.tab == tab
        return Button {
            model.tab = tab
        } label: {
            HStack(spacing: 6) {
                Image(nsImage: icon)
                Text(title)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 5).fill(isSelected ? Color(nsColor: .quaternaryLabelColor) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var grid: some View {
        if model.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.sources.isEmpty {
            Text(UserText.aiChatScreenshotPickerNoWindows)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .top), count: Self.columnCount),
                              spacing: 12) {
                        ForEach(model.sources) { source in
                            tile(for: source)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                }
                // Keeps the tile chosen with the arrow keys in view.
                .onChange(of: model.selectedID) { id in
                    guard let id else { return }
                    proxy.scrollTo(id)
                }
            }
        }
    }

    private func tile(for source: AIChatScreenshotSource) -> some View {
        let isSelected = model.selectedID == source.id
        let shape = RoundedRectangle(cornerRadius: 8)
        return VStack(spacing: 0) {
            // Fills the tile and crops the overflow, centered.
            Color.clear
                .frame(height: Self.thumbnailHeight)
                .overlay(thumbnail(for: source))
                .clipped()
            Divider()
            HStack(spacing: 6) {
                icon(for: source)
                Text(source.title)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(shape)
        .overlay(shape.strokeBorder(isSelected ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: isSelected ? 3 : 1))
        .contentShape(shape)
        .help(source.subtitle.map { "\($0) — \(source.title)" } ?? source.title)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(source.subtitle.map { "\($0), \(source.title)" } ?? source.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.selectedID = source.id }
        .accessibilityAction(named: Text(UserText.aiChatScreenshotPickerCapture)) { model.share(source.id) }
        // The first click selects right away; the second click of a double-click captures.
        .gesture(TapGesture(count: 2).onEnded { model.share(source.id) })
        .simultaneousGesture(TapGesture().onEnded { model.selectedID = source.id })
    }

    @ViewBuilder
    private func thumbnail(for source: AIChatScreenshotSource) -> some View {
        if let thumbnail = model.thumbnails[source.id] {
            if let thumbnail {
                Image(decorative: thumbnail, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        } else {
            ProgressView()
                .controlSize(.small)
        }
    }

    @ViewBuilder
    private func icon(for source: AIChatScreenshotSource) -> some View {
        if let icon = source.icon {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 14, height: 14)
        } else {
            Image(nsImage: DesignSystemImages.Glyphs.Size16.deviceDesktop)
                .resizable()
                .frame(width: 14, height: 14)
        }
    }
}
