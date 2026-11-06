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

enum AssistedOptOutPalette {
    static let agent = NSColor(srgbRed: 0xF0 / 255, green: 0x5F / 255, blue: 0x2B / 255, alpha: 1)
    static let user = NSColor(srgbRed: 0xF5 / 255, green: 0xA6 / 255, blue: 0x23 / 255, alpha: 1)
}

extension AssistedOptOut.DataBroker {
    /// Broker URLs are sometimes stored as a bare domain.
    var homeURL: URL? {
        if let url = URL(string: url), url.host != nil { return url }
        return URL(string: "https://\(url)")
    }
}

/// The attempt's address, and whether its web view has shown a real page yet.
@MainActor
final class AssistedOptOutPageModel: ObservableObject {
    @Published private(set) var url: URL?
    @Published private(set) var hasLoadedPage = false
    private var observations: [NSKeyValueObservation] = []

    /// The runner first loads a simulated `dbp://blank` page, and the web view reports the broker's URL as soon as that
    /// navigation starts, while still drawing the simulated page. So the page counts as loaded only when a load finishes
    /// on a web URL.
    func observe(_ webView: WKWebView) {
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

/// Never sizes its window: the SwiftUI content fits whatever space the window gives it.
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

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}

/// The bar above the web view: the page's site and path, and who is in control.
struct AssistedOptOutTopBar: View {
    @ObservedObject var session: AssistedOptOutSession
    @ObservedObject var page: AssistedOptOutPageModel

    var body: some View {
        HStack(spacing: 12) {
            address
            Spacer(minLength: 0)
            status
                .fixedSize()
                .layoutPriority(1)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(designSystemColor: .surfaceSecondary))
    }

    private var address: some View {
        let url = page.url ?? session.broker.homeURL
        let host = url?.host.map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 } ?? session.broker.url
        let path = url?.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
        return HStack(spacing: 8) {
            if url?.scheme == "https" {
                Image(nsImage: DesignSystemImages.Glyphs.Size16.lock)
                    .renderingMode(.template)
                    .foregroundColor(Color(designSystemColor: .iconsSecondary))
            }
            (Text(host).fontWeight(.medium).foregroundColor(Color(designSystemColor: .textPrimary))
             + Text(path.isEmpty ? "" : " / \(path)").foregroundColor(Color(designSystemColor: .textSecondary)))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    @ViewBuilder
    private var status: some View {
        switch session.phase {
        case .ready:
            Text("Not started")
                .foregroundColor(Color(designSystemColor: .textSecondary))
        case .queued, .agentInControl:
            statusLabel("DuckDuckGo is in control", dot: Color(nsColor: AssistedOptOutPalette.agent))
        case .userTurn:
            statusLabel("DuckDuckGo is waiting for you", dot: Color(nsColor: AssistedOptOutPalette.user))
        case .submitted:
            statusLabel("Finished", dot: Color(designSystemColor: .statusGreen))
        }
    }

    private func statusLabel(_ title: String, dot: Color) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(dot)
                .frame(width: 8, height: 8)
            Text(title)
                .fontWeight(.medium)
                .foregroundColor(Color(designSystemColor: .textPrimary))
        }
    }
}

/// Rounded frame around the web view that glows orange while DuckDuckGo is in control, and yellow on the user's turn.
final class AssistedOptOutGlowFrameView: NSView {
    enum Glow {
        case none
        case agent
        case user
    }

    private static let cornerRadius: CGFloat = 14
    private static let borderWidth: CGFloat = 3
    private static let ringWidth: CGFloat = 4
    private static let pulseKey = "pulse"

    let contentView = NSView()
    private let ringLayer = CALayer()
    private var glow = Glow.none

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.cornerRadius = Self.cornerRadius
        layer?.borderWidth = Self.borderWidth
        layer?.borderColor = NSColor.clear.cgColor
        layer?.shadowOffset = .zero
        layer?.shadowRadius = 14
        layer?.shadowOpacity = 0
        ringLayer.cornerRadius = Self.cornerRadius + Self.ringWidth
        ringLayer.borderWidth = Self.ringWidth
        ringLayer.borderColor = NSColor.clear.cgColor
        layer?.addSublayer(ringLayer)

        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = Self.cornerRadius - Self.borderWidth
        contentView.layer?.masksToBounds = true
        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: topAnchor, constant: Self.borderWidth),
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.borderWidth),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.borderWidth),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.borderWidth)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: Self.cornerRadius, cornerHeight: Self.cornerRadius, transform: nil)
        ringLayer.frame = bounds.insetBy(dx: -Self.ringWidth, dy: -Self.ringWidth)
        CATransaction.commit()
    }

    func setGlow(_ glow: Glow) {
        guard glow != self.glow else { return }
        self.glow = glow
        layer?.removeAnimation(forKey: Self.pulseKey)

        let color: NSColor
        switch glow {
        case .none:
            layer?.borderColor = NSColor.clear.cgColor
            layer?.shadowOpacity = 0
            ringLayer.borderColor = NSColor.clear.cgColor
            return
        case .agent: color = AssistedOptOutPalette.agent
        case .user: color = AssistedOptOutPalette.user
        }
        layer?.borderColor = color.cgColor
        layer?.shadowColor = color.cgColor
        layer?.shadowRadius = 14
        layer?.shadowOpacity = 0.35
        ringLayer.borderColor = color.withAlphaComponent(0.18).cgColor

        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let radius = CABasicAnimation(keyPath: "shadowRadius")
        radius.toValue = glow == .user ? 22 : 20
        let opacity = CABasicAnimation(keyPath: "shadowOpacity")
        opacity.toValue = glow == .user ? 0.45 : 0.28
        let pulse = CAAnimationGroup()
        pulse.animations = [radius, opacity]
        pulse.duration = glow == .user ? 0.8 : 1.2
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer?.add(pulse, forKey: Self.pulseKey)
    }
}

/// Covers the web view: the intro before the attempt starts, then a placeholder until the broker's page has loaded.
struct AssistedOptOutPageCover: View {
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
        .background(Color(designSystemColor: .surfacePrimary))
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
            .fill(Color(designSystemColor: .controlsFillPrimary))
            .frame(width: width, height: height)
    }
}
