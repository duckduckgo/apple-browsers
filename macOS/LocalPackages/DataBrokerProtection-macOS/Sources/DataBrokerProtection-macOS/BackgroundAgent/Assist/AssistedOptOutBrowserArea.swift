//
//  AssistedOptOutBrowserArea.swift
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
import ConcurrencyExtensions
import DataBrokerProtectionCore
import DesignResourcesKit
import DesignResourcesKitIcons
import SwiftUI
import WebKit

extension AssistedOptOut.DataBroker {
    var homeURL: URL? {
        if let url = URL(string: url), url.host != nil { return url }
        return URL(string: "https://\(url)")
    }
}

@MainActor
final class AssistedOptOutPageModel: ObservableObject {
    @Published private(set) var url: URL?
    @Published private(set) var hasLoadedPage = false
    private var observations: [NSKeyValueObservation] = []

    // A broker URL appears before the simulated blank page is replaced. Reveal only after a web load finishes.
    func observe(_ webView: WKWebView) {
        stopObserving()
        observations = [
            webView.observe(\.url, options: [.initial, .new]) { [weak self] webView, _ in
                let url = webView.url.flatMap { Self.isWebURL($0) ? $0 : nil }
                MainActor.assumeMainThread {
                    self?.url = url
                }
            },
            webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] webView, _ in
                let hasLoadedWebPage = !webView.isLoading && webView.url.map(Self.isWebURL) == true
                MainActor.assumeMainThread {
                    if hasLoadedWebPage { self?.revealPage() }
                }
            }
        ]
    }

    func revealPage() {
        guard !hasLoadedPage else { return }
        hasLoadedPage = true
    }

    func stopObserving() {
        observations.forEach { $0.invalidate() }
        observations = []
    }

    private nonisolated static func isWebURL(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme)
    }
}

final class AssistedOptOutHostingView<Content: View>: NSHostingView<Content> {
    required init(rootView: Content) {
        super.init(rootView: rootView)
        if #available(macOS 13.0, *) {
            sizingOptions = []
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
final class AssistedOptOutBackgroundView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        applyBackground()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyBackground()
    }

    private func applyBackground() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor(designSystemColor: .surfacePrimary, palette: .default).cgColor
        }
    }
}

@MainActor
struct AssistedOptOutAppearanceRoot<Content: View>: View {
    let content: Content

    var body: some View {
        content
            .environment(\.designSystemPalette, ColorPalette.default)
    }
}

@MainActor
struct AssistedOptOutAddress: View {
    // Toolbar items with a width constraint get a different corner radius, so the address is shortened instead.
    private static let maxPathLength = 40

    @Environment(\.designSystemPalette) private var palette
    @ObservedObject var session: AssistedOptOutSession
    @ObservedObject var page: AssistedOptOutPageModel

    var body: some View {
        let url = page.url ?? session.broker.homeURL
        let host = url?.host.map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 } ?? session.broker.url
        let fullPath = url?.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
        let path = fullPath.count > Self.maxPathLength ? String(fullPath.prefix(Self.maxPathLength - 1)) + "…" : fullPath
        return HStack(spacing: 8) {
            if url?.scheme == "https" {
                Image(nsImage: DesignSystemImages.Glyphs.Size16.lock)
                    .renderingMode(.template)
                    .foregroundColor(Color(designSystemColor: .iconsSecondary, palette: palette))
                    .accessibilityHidden(true)
            }
            (Text(host).fontWeight(.medium).foregroundColor(Color(designSystemColor: .textPrimary, palette: palette))
             + Text(path.isEmpty ? "" : " / \(path)").foregroundColor(Color(designSystemColor: .textSecondary, palette: palette)))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AssistedOptOutText.pageAddress(url?.absoluteString ?? session.broker.url))
    }
}

@MainActor
struct AssistedOptOutStatus: View {
    @Environment(\.designSystemPalette) private var palette
    @ObservedObject var session: AssistedOptOutSession

    var body: some View {
        Group {
            switch session.phase {
            case .ready:
                Text(AssistedOptOutText.notStarted)
                    .foregroundColor(Color(designSystemColor: .textSecondary, palette: palette))
            case .queued, .agentInControl:
                label(AssistedOptOutText.agentInControl, dot: Color(designSystemColor: .accentFirePrimary, palette: palette))
            case .userTurn:
                label(AssistedOptOutText.waitingForYou, dot: Color(designSystemColor: .statusYellowPrimary, palette: palette))
            case .submitted:
                label(AssistedOptOutText.finished, dot: Color(designSystemColor: .statusGreen, palette: palette))
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 12)
        .fixedSize()
    }

    private func label(_ title: String, dot: Color) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(dot)
                .frame(width: 8, height: 8)
            Text(title)
                .fontWeight(.medium)
                .foregroundColor(Color(designSystemColor: .textPrimary, palette: palette))
        }
    }
}

@MainActor
final class AssistedOptOutEdgeOverlayView: NSView {
    enum Edge {
        case none
        case agent
        case user
    }

    private static let edgeWidth: CGFloat = 3
    private static let glowRadius: CGFloat = 16
    private static let pulseKey = "pulse"

    private let edgeLayer = CALayer()
    private let innerShadowLayer = CAShapeLayer()
    private var edge = Edge.none

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        innerShadowLayer.fillRule = .evenOdd
        innerShadowLayer.fillColor = NSColor.clear.cgColor
        innerShadowLayer.shadowOffset = .zero
        innerShadowLayer.shadowRadius = Self.glowRadius
        innerShadowLayer.shadowOpacity = 0
        edgeLayer.borderWidth = Self.edgeWidth
        edgeLayer.borderColor = NSColor.clear.cgColor
        layer?.addSublayer(innerShadowLayer)
        layer?.addSublayer(edgeLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        edgeLayer.frame = bounds
        innerShadowLayer.frame = bounds
        innerShadowLayer.path = Self.ringPath(outside: bounds, width: Self.glowRadius * 3)
        CATransaction.commit()
    }

    private static func ringPath(outside rect: CGRect, width: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addRect(rect.insetBy(dx: -width, dy: -width))
        path.addRect(rect)
        return path
    }

    func setEdge(_ edge: Edge) {
        guard edge != self.edge else { return }
        self.edge = edge
        applyEdge()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyEdge()
    }

    private func applyEdge() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            updateEdgeColors()
        }
    }

    private func updateEdgeColors() {
        innerShadowLayer.removeAnimation(forKey: Self.pulseKey)
        let color: NSColor
        switch edge {
        case .none:
            edgeLayer.borderColor = NSColor.clear.cgColor
            innerShadowLayer.fillColor = NSColor.clear.cgColor
            innerShadowLayer.shadowOpacity = 0
            return
        case .agent: color = NSColor(designSystemColor: .accentFirePrimary, palette: .default)
        case .user: color = NSColor(designSystemColor: .statusYellowPrimary, palette: .default)
        }
        edgeLayer.borderColor = color.cgColor
        innerShadowLayer.fillColor = color.cgColor
        innerShadowLayer.shadowColor = color.cgColor
        innerShadowLayer.shadowOpacity = 0.5

        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let pulse = CABasicAnimation(keyPath: "shadowOpacity")
        pulse.fromValue = edge == .user ? 0.8 : 0.5
        pulse.toValue = edge == .user ? 0.3 : 0.25
        pulse.duration = edge == .user ? 0.8 : 1.2
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        innerShadowLayer.add(pulse, forKey: Self.pulseKey)
    }
}

@MainActor
struct AssistedOptOutPageCover: View {
    @Environment(\.designSystemPalette) private var palette
    @ObservedObject var session: AssistedOptOutSession

    var body: some View {
        Group {
            if session.phase == .ready {
                AssistedOptOutIntroView(session: session)
            } else {
                loadingPlaceholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(designSystemColor: .surfacePrimary, palette: palette))
    }

    private var loadingPlaceholder: some View {
        VStack(alignment: .leading, spacing: 14) {
            skeletonLine(width: 180, height: 14)
            skeletonLine(width: 360, height: 10)
            skeletonLine(width: 270, height: 10)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func skeletonLine(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color(designSystemColor: .controlsFillPrimary, palette: palette))
            .frame(width: width, height: height)
    }
}
