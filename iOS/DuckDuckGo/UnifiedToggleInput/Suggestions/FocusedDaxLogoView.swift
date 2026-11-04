//
//  FocusedDaxLogoView.swift
//  DuckDuckGo
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

import Lottie
import SwiftUI

/// The focused-omnibar empty-state logo, morphing Dax ↔ Duck.ai via a bound `progress`
/// (0 = Dax/search, 1 = Duck.ai). Renders through the same Lottie asset as `NewTabPageDaxLogoView`
/// so the focused and NTP logos stay pixel-identical. No positioning or visibility logic — the host owns that.
struct FocusedDaxLogoView: View {
    static let size = CGSize(width: 210, height: 162)

    @Environment(\.colorScheme) private var colorScheme

    /// 0 = Dax (search), 1 = Duck.ai.
    let progress: CGFloat
    /// When true, animate the morph from the current frame to `progress`; when false, jump straight to
    /// it (used when the logo is crossfading in/out against favorites/lists, where a morph isn't wanted).
    var morph: Bool = true
    /// Playback rate for the morph. >1 finishes faster — used so a dismiss morph fits inside the
    /// (shorter) bar collapse instead of being cut off.
    var animationSpeed: Double = 1
    /// Holds the current frame, so a logo fading out for lack of room does not morph on the way.
    var freezes = false
    /// A logo built while it has no room has no frame to hold yet, so it only freezes once it has shown.
    @State private var hasShown = false
    /// The mark the logo rests at once a morph has finished, or once a freeze ends: a frozen logo was hidden,
    /// so it reappears at rest instead of morphing from the held frame, which can be the other mode's mark.
    /// Resting also keeps a finished morph from replaying when the app returns from the background.
    @State private var restingProgress: CGFloat?

    private var animationName: String {
        colorScheme == .dark ? Constant.darkAnimationName : Constant.animationName
    }

    private var playbackMode: LottiePlaybackMode {
        if freezes && hasShown { return .paused(at: .currentFrame) }
        if restingProgress == progress { return .paused(at: .progress(progress)) }
        return morph ? .playing(.toProgress(progress, loopMode: .playOnce)) : .paused(at: .progress(progress))
    }

    var body: some View {
        Lottie.LottieView(animation: LottieAnimation.named(animationName))
            .playbackMode(playbackMode)
            .animationSpeed(animationSpeed)
            .animationDidFinish { if $0 { restingProgress = progress } }
            .frame(height: Self.size.height)
            .id(animationName)
            .onAppear { hasShown = hasShown || !freezes }
            .onChange(of: freezes) { freezes in
                if !freezes && hasShown { restingProgress = progress }
                hasShown = hasShown || !freezes
            }
            // A later mode switch morphs as usual.
            .onChange(of: progress) { if $0 != restingProgress { restingProgress = nil } }
    }

    private enum Constant {
        static let animationName = "duckduckgo-ai-transition.json"
        static let darkAnimationName = "duckduckgo-ai-transition-dark.json"
    }
}

struct EscapeHatchLogoLayout: AnimatableModifier {
    var centerY: CGFloat
    var viewport: CGRect
    let hatchFrame: CGRect?
    private let fitsAtDestination: Bool
    private let followsHatch: Bool
    private let destinationCenterY: CGFloat
    private let destinationViewport: CGRect
    var retainedFrame: CGRect?
    var animatesVisibility = true

    init(centerY: CGFloat, viewport: CGRect, hatchFrame: CGRect?, destinationHatchFrame: CGRect?, fitsMargins: Bool = true,
         followsHatch: Bool = false) {
        self.centerY = centerY
        self.viewport = viewport
        self.hatchFrame = hatchFrame
        self.destinationCenterY = centerY
        self.destinationViewport = viewport
        self.followsHatch = followsHatch
        // A logo squeezed between the hatch and the keyboard/input bar does not fit, even without overlap.
        fitsAtDestination = fitsMargins && Self.fits(centerY: centerY, viewport: viewport, hatchFrame: destinationHatchFrame)
    }

    var animatableData: AnimatablePair<CGFloat, CGRect.AnimatableData> {
        get { AnimatablePair(centerY, viewport.animatableData) }
        set {
            centerY = newValue.first
            viewport.animatableData = newValue.second
        }
    }

    func body(content: Content) -> some View {
        content
            .offset(y: retainedFrame?.midY ?? displayedCenterY)
            // Check the animated position so a growing viewport cannot reveal an overlapping logo.
            .opacity(retainedFrame != nil || isVisible ? 1 : 0)
            .animation(animatesVisibility ? FocusedContentFade.fadeIn : nil, value: isVisible)
    }

    /// Where the logo rests once its animation settles, or nil when it does not fit there.
    var visibleFrame: CGRect? {
        guard fitsAtDestination else { return nil }
        let size = FocusedDaxLogoView.size
        return CGRect(x: destinationViewport.midX - size.width / 2, y: destinationCenterY - size.height / 2,
                      width: size.width, height: size.height)
    }

    var isVisible: Bool {
        fitsAtDestination && Self.fits(centerY: displayedCenterY, viewport: viewport, hatchFrame: hatchFrame)
    }

    /// A logo below a hatch it follows never gets ahead of it, as the two animate at different speeds.
    private var displayedCenterY: CGFloat {
        guard followsHatch, let hatchFrame, hatchFrame.midY < centerY else { return centerY }
        return max(centerY, hatchFrame.maxY + FocusedDaxLogoView.size.height / 2)
    }

    private static func fits(centerY: CGFloat, viewport: CGRect, hatchFrame: CGRect?) -> Bool {
        guard let hatchFrame, !viewport.isEmpty else { return false }
        let size = FocusedDaxLogoView.size
        // Half a point absorbs the rounding left when the logo is placed exactly against the hatch.
        let logoFrame = CGRect(x: viewport.midX - size.width / 2, y: centerY - size.height / 2,
                               width: size.width, height: size.height).insetBy(dx: 0, dy: 0.5)
        let overlap = logoFrame.intersection(hatchFrame)
        return viewport.contains(logoFrame) && overlap.isEmpty
    }
}

struct FocusedLogoLayout {
    static let screenCenterOffset: CGFloat = 55
    let centerY: CGFloat
    let hatchLayout: EscapeHatchLogoLayout?
    let frame: CGRect

    init(viewport: CGRect, chromeInsetTop: CGFloat, placement: FocusedContentPlacement,
         hatchFrame: CGRect?, destinationHatchFrame: CGRect?, restingCenterY: CGFloat) {
        let chromeFrame = CGRect(x: viewport.minX, y: viewport.minY, width: viewport.width, height: chromeInsetTop)
        let clearance = Self.logoTopClearance(chromeBottom: chromeFrame.maxY,
                                             embeddedHatchFrame: placement == .embedded ? destinationHatchFrame : nil)
        centerY = Self.logoCenterY(restingAt: restingCenterY, topChromeBottom: clearance, barTop: viewport.maxY)
        let size = FocusedDaxLogoView.size
        frame = CGRect(x: viewport.midX - size.width / 2, y: centerY - size.height / 2, width: size.width, height: size.height)
        if placement == .hidden {
            hatchLayout = nil
        } else {
            let availableViewport = CGRect(x: viewport.minX, y: chromeFrame.maxY, width: viewport.width,
                                           height: max(0, viewport.maxY - chromeFrame.maxY))
            let isPinned = placement == .pinned
            hatchLayout = EscapeHatchLogoLayout(centerY: centerY, viewport: availableViewport,
                                                hatchFrame: isPinned ? chromeFrame : hatchFrame,
                                                destinationHatchFrame: isPinned ? chromeFrame : destinationHatchFrame,
                                                fitsMargins: Self.logoFits(topChromeBottom: clearance, barTop: viewport.maxY),
                                                followsHatch: !isPinned)
        }
    }

    static func logoTopClearance(chromeBottom: CGFloat, embeddedHatchFrame: CGRect?) -> CGFloat {
        max(chromeBottom, (embeddedHatchFrame?.maxY ?? -.infinity) - Metrics.topChromeGap)
    }

    static func logoCenterY(restingAt restCenterY: CGFloat, topChromeBottom: CGFloat, barTop: CGFloat) -> CGFloat {
        let halfHeight = FocusedDaxLogoView.size.height / 2
        guard logoFits(topChromeBottom: topChromeBottom, barTop: barTop) else { return (topChromeBottom + barTop) / 2 }
        return min(max(restCenterY, topChromeBottom + Metrics.topChromeGap + halfHeight), barTop - Metrics.bottomBarGap - halfHeight)
    }

    static func logoFits(topChromeBottom: CGFloat, barTop: CGFloat) -> Bool {
        topChromeBottom + Metrics.topChromeGap + FocusedDaxLogoView.size.height <= barTop - Metrics.bottomBarGap
    }

    private enum Metrics {
        static let topChromeGap: CGFloat = 16
        static let bottomBarGap: CGFloat = 56
    }
}

struct EmbeddedEscapeHatchGeometry: Equatable {
    let frame: CGRect
    var appliedContentTopInset: CGFloat = 0

    func destinationFrame(contentTopInset: CGFloat) -> CGRect {
        frame.offsetBy(dx: 0, dy: contentTopInset - appliedContentTopInset)
    }
}

struct EmbeddedEscapeHatchGeometryKey: PreferenceKey {
    static var defaultValue: EmbeddedEscapeHatchGeometry?

    static func reduce(value: inout EmbeddedEscapeHatchGeometry?, nextValue: () -> EmbeddedEscapeHatchGeometry?) {
        if let next = nextValue(), !next.frame.isEmpty { value = next }
    }
}

struct EmbeddedEscapeHatchGeometryReader: ViewModifier {
    /// Set on the focused scroll view; its content's offset in this space is the scroll displacement.
    static let scrollSpace = "EmbeddedEscapeHatchScroll"
    /// Set on the focused scroll content, which rests at the top of `scrollSpace`.
    static let contentSpace = "EmbeddedEscapeHatchContent"
    var traceContext: String?

    private struct TraceFrames: Equatable {
        let global: CGRect
        let scroll: CGRect
        let content: CGRect
        let resting: CGRect
    }

    func body(content: Content) -> some View {
        content.background {
            GeometryReader { geometry in
                let frames = TraceFrames(global: geometry.frame(in: .global),
                                         scroll: geometry.frame(in: .named(Self.scrollSpace)),
                                         content: geometry.frame(in: .named(Self.contentSpace)),
                                         resting: Self.restingFrame(of: geometry))
                Color.clear.preference(key: EmbeddedEscapeHatchGeometryKey.self,
                                       value: EmbeddedEscapeHatchGeometry(frame: Self.restingFrame(of: geometry)))
                    .onAppear { logTrace("appear", frames: frames) }
                    .onChange(of: frames) { logTrace("changed", frames: $0) }
            }
        }
    }

    private func logTrace(_ event: String, frames: TraceFrames) {
        guard let traceContext else { return }
        print("[UTI_LOGO_TIMING] \(String(format: "%.6f", ProcessInfo.processInfo.systemUptime)) hatch.geometry event=\(event) \(traceContext) rawGlobal=\(frames.global) namedScroll=\(frames.scroll) namedContent=\(frames.content) resting=\(frames.resting)")
    }

    /// The hatch frame with scrolling removed, so the logo neither follows nor reacts to a scroll.
    /// Outside the focused scroll view both spaces resolve to global and nothing is removed.
    private static func restingFrame(of geometry: GeometryProxy) -> CGRect {
        let scrollOffset = geometry.frame(in: .named(scrollSpace)).minY - geometry.frame(in: .named(contentSpace)).minY
        return geometry.frame(in: .global).offsetBy(dx: 0, dy: -scrollOffset)
    }
}

struct FocusedContentTopInset: AnimatableModifier {
    var topInset: CGFloat
    var fixedTopInset: CGFloat = 0
    var onEscapeHatchGeometryChange: ((EmbeddedEscapeHatchGeometry?) -> Void)?

    var animatableData: CGFloat {
        get { topInset }
        set { topInset = newValue }
    }

    func body(content: Content) -> some View {
        content
            .padding(.top, fixedTopInset + topInset)
            .coordinateSpace(name: EmbeddedEscapeHatchGeometryReader.contentSpace)
            .transformPreference(EmbeddedEscapeHatchGeometryKey.self) { geometry in
                geometry?.appliedContentTopInset = topInset
            }
            .onPreferenceChange(EmbeddedEscapeHatchGeometryKey.self) { geometry in
                onEscapeHatchGeometryChange?(geometry)
            }
    }
}
