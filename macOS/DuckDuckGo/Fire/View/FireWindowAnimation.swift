//
//  FireWindowAnimation.swift
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
import Combine
import Common
import Lottie
import QuartzCore

/// The visible replacement is installed before the source is ordered out. It owns no browser views.
@MainActor
final class FireWindowAnimationController: NSWindowController {
    final class SnapshotWindow: NSWindow {
        override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
            // The captured shadow can extend above the screen's visible area. AppKit's default
            // constraint would move the entire snapshot down, especially on a secondary display.
            frameRect
        }
    }

    private static var active = [UUID: FireWindowAnimationController]()
    private let identifier = UUID()
    private let snapshotLayer = CALayer()
    private let contentBounds: CGRect
    private var completion: (() -> Void)?
    private var animationTask: Task<Void, Never>?
    private var fireAnimationView: LottieAnimationView?
    private var didFinish = false

    init?(sourceWindow: NSWindow) {
        guard sourceWindow.isVisible else { return nil }
        let sourceFrame = sourceWindow.frame
        // Capture the native shadow in a known screen rectangle instead of approximating it.
        let padding: CGFloat = 80
        let frame = sourceFrame.insetBy(dx: -padding, dy: -padding)
        let windowID = CGWindowID(sourceWindow.windowNumber)
        guard let info = CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID) as? [[String: Any]],
              let bounds = info.first?[kCGWindowBounds as String] as? [String: Any],
              let captureBounds = CGRect(dictionaryRepresentation: bounds as CFDictionary),
              let image = CGWindowListCreateImage(captureBounds.insetBy(dx: -padding, dy: -padding),
                                                  .optionIncludingWindow, windowID, [.bestResolution]) else { return nil }
        contentBounds = CGRect(origin: CGPoint(x: padding, y: padding), size: sourceFrame.size)
        let window = SnapshotWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = sourceWindow.level
        window.collectionBehavior = [.fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.animationBehavior = .none
        super.init(window: window)
        let view = NSView(frame: CGRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        window.contentView = view
        snapshotLayer.frame = view.bounds
        snapshotLayer.contents = image
        snapshotLayer.contentsScale = sourceWindow.backingScaleFactor
        view.layer?.addSublayer(snapshotLayer)

        Self.active[identifier] = self
        // Commit the replacement and removal together; flushing between them doubles the shadow for a frame.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            window.order(.above, relativeTo: sourceWindow.windowNumber)
            window.displayIfNeeded()
            // Browser windows use .documentWindow, whose native fade outlives this zero-duration group.
            // Disable it for the handoff so the captured shadow never overlaps a fading live shadow.
            let behavior = sourceWindow.animationBehavior
            sourceWindow.animationBehavior = .none
            sourceWindow.orderOut(nil)
            sourceWindow.animationBehavior = behavior
        }
    }

    required init?(coder: NSCoder) {
        fatalError("FireWindowAnimationController: Bad initializer")
    }

    deinit {
        animationTask?.cancel()
    }

    func start(completion: @escaping () -> Void) {
        self.completion = completion
        // Test runs skip the visual treatment, but preserve start/finish notifications.
        guard case .normal = AppVersion.runType else {
            finish()
            return
        }
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            animationTask = Task { [weak self] in
                let fire = await DefaultFireAnimationLoader.shared.load()
                guard !Task.isCancelled, let self else { return }
                guard let fire else {
                    finish()
                    return
                }
                animateFire(fire)
            }
            return
        }
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            Task { @MainActor in self?.finish() }
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = 0.15
        snapshotLayer.opacity = 0
        snapshotLayer.add(fade, forKey: "fade")
        CATransaction.commit()
    }

    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        fireAnimationView?.stop()
        fireAnimationView = nil
        animationTask = nil
        window?.orderOut(nil)
        window?.close()
        let completion = self.completion
        self.completion = nil
        Self.active[identifier] = nil
        completion?()
    }

    /// The bundled GPU-rendered Lottie asset supplies both the flames and the wipe geometry.
    private func animateFire(_ fire: DefaultFireAnimation) {
        guard let view = window?.contentView else { return }
        let animationView = LottieAnimationView(animation: fire.animation, configuration: LottieConfiguration(renderingEngine: .coreAnimation))
        animationView.identifier = .init(rawValue: DefaultFireAnimationLoader.assetName)
        animationView.frame = contentBounds
        animationView.contentMode = .scaleToFill
        view.addSubview(animationView)
        fireAnimationView = animationView

        let paths = fire.burnFronts.map { front -> CGPath in
            let path = CGMutablePath()
            let size = snapshotLayer.bounds.size
            func height(_ value: CGFloat) -> CGFloat {
                if value < 0 { return 0 }
                if value >= 1 { return size.height }
                return contentBounds.minY + value * contentBounds.height
            }
            path.move(to: CGPoint(x: 0, y: size.height))
            path.addLine(to: CGPoint(x: 0, y: height(front[0])))
            for (index, value) in front.enumerated() {
                let x = contentBounds.minX + CGFloat(index) / CGFloat(front.count - 1) * contentBounds.width
                path.addLine(to: CGPoint(x: x, y: height(value)))
            }
            path.addLine(to: CGPoint(x: size.width, y: height(front[front.count - 1])))
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.closeSubpath()
            return path
        }
        let mask = CAShapeLayer()
        mask.frame = snapshotLayer.bounds
        mask.path = paths.last
        snapshotLayer.mask = mask
        let wipe = CAKeyframeAnimation(keyPath: "path")
        wipe.values = paths
        wipe.duration = fire.animation.duration
        wipe.calculationMode = .linear
        mask.add(wipe, forKey: "lottieBurnFront")
        animationView.play(fromProgress: 0, toProgress: 1) { [weak self] _ in
            self?.finish()
        }
    }

}

/// Normalized, cumulative flame fronts sampled from the bundled Lottie shapes.
struct DefaultFireAnimation: Sendable {
    let animation: LottieAnimation
    let burnFronts: [[CGFloat]]
}

/// Prepare the bundled asset and its wipe off the main actor, once for all browser windows.
actor DefaultFireAnimationLoader {
    static let shared = DefaultFireAnimationLoader()
    static let assetName = "02_Fire_rebranded"
    private var cached: DefaultFireAnimation?

    func load() -> DefaultFireAnimation? {
        if let cached { return cached }
        guard let animation = LottieAnimation.named(Self.assetName, animationCache: LottieAnimationCache.shared),
              let fronts = sampleBurnFronts(animation) else { return nil }
        let fire = DefaultFireAnimation(animation: animation, burnFronts: fronts)
        cached = fire
        return fire
    }

    private func sampleBurnFronts(_ animation: LottieAnimation) -> [[CGFloat]]? {
        let width = 136
        let height = max(1, Int((CGFloat(width) * animation.bounds.height / animation.bounds.width).rounded()))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let bytes = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        let renderer = LottieAnimationLayer(animation: animation, configuration: LottieConfiguration(renderingEngine: .mainThread))
        renderer.frame = animation.bounds
        renderer.animationLayer?.position = CGPoint(x: animation.bounds.midX, y: animation.bounds.midY)
        let frames = max(1, Int(ceil(animation.endFrame - animation.startFrame)))
        var front = [CGFloat](repeating: -1, count: width)
        return (0...frames).map { frame in
            renderer.currentFrame = animation.startFrame + CGFloat(frame) / CGFloat(frames) * (animation.endFrame - animation.startFrame)
            renderer.forceDisplayUpdate()
            renderer.layoutIfNeeded()
            context.clear(CGRect(x: 0, y: 0, width: width, height: height))
            context.saveGState()
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: CGFloat(width) / animation.bounds.width, y: -CGFloat(height) / animation.bounds.height)
            // Sample solid vector silhouettes; rasterizing Lottie's gradients here would be expensive.
            paintFlameShapes(renderer, relativeTo: renderer, in: context)
            context.restoreGState()
            for x in 0..<width {
                for y in 0..<height where bytes[(y * width + x) * 4 + 3] > 128 {
                    front[x] = max(front[x], 1 - CGFloat(y) / CGFloat(height))
                    break
                }
            }
            if frame == frames { front = [CGFloat](repeating: 1, count: width) }
            return front
        }
    }

    private func paintFlameShapes(_ layer: CALayer, relativeTo root: CALayer, in context: CGContext) {
        guard !layer.isHidden, layer.opacity > 0 else { return }
        context.saveGState()
        if layer.masksToBounds { context.clip(to: layer.convert(layer.bounds, to: root)) }
        if let path = (layer as? CAShapeLayer)?.path {
            let origin = layer.convert(CGPoint.zero, to: root)
            let x = layer.convert(CGPoint(x: 1, y: 0), to: root)
            let y = layer.convert(CGPoint(x: 0, y: 1), to: root)
            var transform = CGAffineTransform(a: x.x - origin.x, b: x.y - origin.y,
                                              c: y.x - origin.x, d: y.y - origin.y, tx: origin.x, ty: origin.y)
            if let path = path.copy(using: &transform) {
                context.addPath(path)
                context.setFillColor(CGColor(gray: 1, alpha: 1))
                context.fillPath()
            }
        }
        for child in layer.sublayers ?? [] { paintFlameShapes(child, relativeTo: root, in: context) }
        context.restoreGState()
    }
}

/// A standalone progress window survives the browser closing and cancels its delayed presentation.
@MainActor
final class FireProgressWindowController: NSWindowController {
    private static var active = [UUID: FireProgressWindowController]()
    private let identifier = UUID()
    private let fireViewModel: FireViewModel
    private var cancellable: AnyCancellable?
    private var pendingPresentation: DispatchWorkItem?
    private var pendingDismissal: DispatchWorkItem?
    private var burnFinished = false
    private var isDismissed = false
    private var animationFinished = false
    private var presentedAt: Date?
    private var progressIndicator: NSProgressIndicator?
    private let message: String
    private let sourceFrame: CGRect

    static func present(fireViewModel: FireViewModel, message: String, sourceWindow: NSWindow, delay: TimeInterval) -> FireProgressWindowController {
        let controller = FireProgressWindowController(fireViewModel: fireViewModel, message: message, sourceWindow: sourceWindow)
        // A previous burn may still be holding its progress panel for the minimum display time.
        for previous in Array(active.values) where previous.fireViewModel === fireViewModel {
            previous.closeProgress()
        }
        active[controller.identifier] = controller
        controller.observe(delay: delay)
        return controller
    }

    private init(fireViewModel: FireViewModel, message: String, sourceWindow: NSWindow) {
        self.fireViewModel = fireViewModel
        self.message = message
        self.sourceFrame = sourceWindow.frame
        super.init(window: nil)
    }

    private func createWindow() {
        let window = NSPanel(contentRect: CGRect(x: sourceFrame.midX - 190, y: sourceFrame.midY - 75, width: 380, height: 150),
                             styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isFloatingPanel = false
        window.hidesOnDeactivate = false
        window.animationBehavior = .alertPanel
        window.setAccessibilityIdentifier("FireProgressWindowController.window")
        window.collectionBehavior = [.fullScreenAuxiliary]
        let label = NSTextField(wrappingLabelWithString: message)
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.alignment = .center
        let spinner = NSProgressIndicator()
        self.progressIndicator = spinner
        spinner.style = .bar
        spinner.isIndeterminate = true
        let stack = NSStackView(views: [label, spinner])
        stack.orientation = .vertical
        stack.spacing = 24
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(stack)
        if let contentView = window.contentView {
            NSLayoutConstraint.activate([
                stack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
                stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
                stack.widthAnchor.constraint(equalToConstant: 320)
            ])
        }
        self.window = window
    }

    required init?(coder: NSCoder) {
        fatalError("FireProgressWindowController: Bad initializer")
    }

    private func observe(delay: TimeInterval) {
        // Receive asynchronously: @Published emits before Fire.burningData itself has changed.
        cancellable = fireViewModel.fire.burningDataPublisher
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] burningData in
                guard let self, !isDismissed else { return }
                if burningData == nil {
                    dismiss()
                } else if burnFinished {
                    // A burn can start before a replacement presenter has subscribed.
                    pendingDismissal?.cancel()
                    pendingDismissal = nil
                    burnFinished = false
                    progressIndicator?.stopAnimation(nil)
                    window?.close()
                    window = nil
                    presentedAt = nil
                }
            }
        schedulePresentation(after: delay)
    }

    private func schedulePresentation(after delay: TimeInterval) {
        pendingPresentation?.cancel()
        let pending = DispatchWorkItem { [weak self] in
            guard let self, !isDismissed, !burnFinished, fireViewModel.isBurning else { return }
            if !fireViewModel.isDataClearingAnimationPlaying || animationFinished {
                if window == nil {
                    createWindow()
                }
                presentedAt = Date()
                let progressWindow = window
                progressIndicator?.startAnimation(nil)
                progressWindow?.orderFront(nil)
            }
        }
        pendingPresentation = pending
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: pending)
    }

    func animationDidFinish() {
        animationFinished = true
        guard !isDismissed, !burnFinished, fireViewModel.isBurning else { return }
        // Let a completed cleanup publish nil before deciding whether a progress window is needed.
        schedulePresentation(after: 0.15)
    }

    private func dismiss() {
        guard !burnFinished, !isDismissed else { return }
        burnFinished = true
        pendingPresentation?.cancel()
        pendingPresentation = nil
        progressIndicator?.stopAnimation(nil)
        let remaining = max(0, 1 - (presentedAt.map { Date().timeIntervalSince($0) } ?? 1))
        let pending = DispatchWorkItem { [weak self] in
            guard let self, !fireViewModel.isBurning else { return }
            closeProgress()
        }
        pendingDismissal = pending
        DispatchQueue.main.asyncAfter(deadline: .now() + remaining, execute: pending)
    }

    private func closeProgress() {
        guard !isDismissed else { return }
        isDismissed = true
        pendingPresentation?.cancel()
        pendingDismissal?.cancel()
        pendingPresentation = nil
        pendingDismissal = nil
        progressIndicator?.stopAnimation(nil)
        window?.close()
        window = nil
        cancellable = nil
        Self.active[identifier] = nil
    }
}
