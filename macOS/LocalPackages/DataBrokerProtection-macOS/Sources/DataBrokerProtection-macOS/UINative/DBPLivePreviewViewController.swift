//
//  DBPLivePreviewViewController.swift
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
import DesignResourcesKitIcons

/// A snapshot of the agent's page beside a checklist of what the agent is doing.
@MainActor
public final class DBPLivePreviewViewController: NSViewController {
    public init(agentInterface: DataBrokerProtectionAppToAgentInterface,
                hidesWhenIdle: Bool = true,
                takeControl: (@MainActor (String) async throws -> Bool)? = nil) {
        self.agentInterface = agentInterface
        self.hidesWhenIdle = hidesWhenIdle
        self.takeControl = takeControl
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Side of the square snapshot of the agent's square web view.
    public static let previewSide: CGFloat = 560
    private static let sidebarWidth: CGFloat = 300
    private static let browserBarHeight: CGFloat = 32
    public static let contentSize = NSSize(width: previewSide + sidebarWidth + 48, height: previewSide + browserBarHeight + 24)

    public override func loadView() {
        let card = PreviewCardView()
        card.material = .popover
        card.blendingMode = .withinWindow
        card.state = .active
        card.wantsLayer = true
        card.layer?.cornerRadius = 16
        card.layer?.masksToBounds = true
        card.alphaValue = hidesWhenIdle ? 0 : 1
        view = card

        browserBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(browserBar)

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.wantsLayer = true
        imageView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        imageView.layer?.cornerRadius = 10
        imageView.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        imageView.layer?.masksToBounds = true
        view.addSubview(imageView)

        overlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(overlay)

        placeholderLabel.font = .systemFont(ofSize: 12)
        placeholderLabel.textColor = .secondaryLabelColor
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(placeholderLabel)

        snapshotButton.title = ""
        snapshotButton.isBordered = false
        snapshotButton.target = self
        snapshotButton.action = #selector(takeControlPressed)
        snapshotButton.isEnabled = false
        snapshotButton.setAccessibilityLabel("Take Control of broker page")
        snapshotButton.toolTip = "Click to Take Control"
        snapshotButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(snapshotButton)

        takeControlButton.title = "Take Control"
        takeControlButton.bezelStyle = .rounded
        takeControlButton.controlSize = .large
        takeControlButton.target = self
        takeControlButton.action = #selector(takeControlPressed)
        takeControlButton.isEnabled = false
        sidebar.setFooter(takeControlButton)
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sidebar)

        NSLayoutConstraint.activate([
            browserBar.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            browserBar.leadingAnchor.constraint(equalTo: imageView.leadingAnchor),
            browserBar.trailingAnchor.constraint(equalTo: imageView.trailingAnchor),
            browserBar.heightAnchor.constraint(equalToConstant: Self.browserBarHeight),
            imageView.topAnchor.constraint(equalTo: browserBar.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            imageView.widthAnchor.constraint(equalToConstant: Self.previewSide),
            imageView.heightAnchor.constraint(equalToConstant: Self.previewSide),
            sidebar.topAnchor.constraint(equalTo: browserBar.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: imageView.bottomAnchor),
            sidebar.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 12),
            sidebar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            sidebar.widthAnchor.constraint(equalToConstant: Self.sidebarWidth),
            overlay.topAnchor.constraint(equalTo: imageView.topAnchor),
            overlay.leadingAnchor.constraint(equalTo: imageView.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: imageView.trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: imageView.bottomAnchor),
            snapshotButton.topAnchor.constraint(equalTo: imageView.topAnchor),
            snapshotButton.leadingAnchor.constraint(equalTo: imageView.leadingAnchor),
            snapshotButton.trailingAnchor.constraint(equalTo: imageView.trailingAnchor),
            snapshotButton.bottomAnchor.constraint(equalTo: imageView.bottomAnchor),
            placeholderLabel.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
            placeholderLabel.centerYAnchor.constraint(equalTo: imageView.centerYAnchor)
        ])
    }

    public override func viewDidAppear() {
        super.viewDidAppear()
        guard timer == nil else { return }
        generation = UUID()
        clearFrame()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.requestFrameIfVisible() }
        }
        requestFrameIfVisible()
    }

    public override func viewWillDisappear() {
        super.viewWillDisappear()
        timer?.invalidate()
        timer = nil
        generation = UUID()
        requestTask?.cancel()
        clearFrame()
    }

    private let agentInterface: DataBrokerProtectionAppToAgentInterface
    private let takeControl: (@MainActor (String) async throws -> Bool)?
    private let takeControlButton = NSButton()
    private let snapshotButton = NSButton()
    private var controlRequestInProgress = false
    private var operationID: String?
    private let hidesWhenIdle: Bool
    private let placeholderLabel = NSTextField(labelWithString: "Waiting for a broker page")
    private let imageView = NSImageView()
    private let browserBar = PIRBrowserBarView()
    private let overlay = PIRAgentOverlayView()
    private let sidebar = PIRStepsSidebarView(width: DBPLivePreviewViewController.sidebarWidth)
    private let faviconSession = URLSession(configuration: .ephemeral)
    private var faviconURL: URL?
    private var faviconTask: Task<Void, Never>?
    private var faviconImages: [URL: NSImage] = [:]
    private var timer: Timer?
    private var requestTask: Task<Void, Never>?
    private var requestStartedAt: Date?
    private var generation = UUID()

    private func requestFrameIfVisible() {
        guard view.window?.isVisible == true, !view.isHiddenOrHasHiddenAncestor else { return }
        if let requestStartedAt {
            if Date().timeIntervalSince(requestStartedAt) > 5 {
                clearFrame(message: "The PIR agent did not respond.")
            }
            return
        }

        requestStartedAt = Date()
        let generation = generation
        let agentInterface = agentInterface
        requestTask = Task { @MainActor [weak self] in
            let result: Result<DBPLivePreviewFrame?, Error>
            do {
                try Task.checkCancellation()
                result = .success(try await agentInterface.getLivePreview())
            } catch {
                result = .failure(error)
            }
            guard let self else { return }
            self.requestStartedAt = nil
            self.requestTask = nil
            guard !Task.isCancelled, self.generation == generation, self.timer != nil,
                  self.view.window?.isVisible == true, !self.view.isHiddenOrHasHiddenAncestor else { return }

            switch result {
            case .success(let frame): self.display(frame)
            case .failure: self.clearFrame(message: "The preview is unavailable.")
            }
        }
    }

    private func display(_ frame: DBPLivePreviewFrame?) {
        guard let frame else {
            clearFrame()
            return
        }
        let image = NSImage(data: frame.imageData).flatMap { $0.size.width > 0 && $0.size.height > 0 ? $0 : nil }
        operationID = frame.operationID
        takeControlButton.title = frame.isManualControl ? "You have control" : "Take Control"
        takeControlButton.isEnabled = frame.canTakeControl && takeControl != nil && !controlRequestInProgress
        snapshotButton.isEnabled = takeControlButton.isEnabled
        imageView.image = image
        if let image {
            overlay.update(target: frame.target, imageSize: image.size,
                           needsAssistance: frame.needsAssistance, isManualControl: frame.isManualControl)
        } else {
            overlay.reset()
            placeholderLabel.stringValue = "Opening \(frame.brokerName)\u{2026}"
        }
        sidebar.update(brokerName: frame.brokerName, checklist: frame.checklist,
                       needsAssistance: frame.needsAssistance, isManualControl: frame.isManualControl)
        browserBar.update(pageURL: frame.pageURL, brokerName: frame.brokerName, isOptOut: frame.checklist?.isOptOut == true,
                          needsAssistance: frame.needsAssistance, isManualControl: frame.isManualControl)
        updateFavicon(frame.faviconURL)
        placeholderLabel.isHidden = image != nil
        view.alphaValue = 1
    }

    private func clearFrame(message: String? = nil) {
        // Keep polling while the card is transparent so a new operation can reveal it.
        view.alphaValue = hidesWhenIdle ? 0 : 1
        operationID = nil
        takeControlButton.isEnabled = false
        snapshotButton.isEnabled = false
        takeControlButton.title = "Take Control"
        updateFavicon(nil)
        imageView.image = nil
        overlay.reset()
        browserBar.reset()
        sidebar.reset(message: message)
        placeholderLabel.stringValue = "Waiting for a broker page"
        placeholderLabel.isHidden = false
    }

    @objc private func takeControlPressed() {
        guard takeControlButton.isEnabled, let operationID, let takeControl else { return }
        controlRequestInProgress = true
        takeControlButton.isEnabled = false
        snapshotButton.isEnabled = false
        Task { @MainActor [weak self] in
            defer { self?.controlRequestInProgress = false }
            do {
                guard try await takeControl(operationID) else {
                    self?.sidebar.showNotice("This step is no longer available.")
                    return
                }
                self?.requestFrameIfVisible()
            } catch {
                self?.sidebar.showNotice("Could not pause this request.")
            }
        }
    }

    private func updateFavicon(_ url: URL?) {
        guard url != faviconURL else { return }
        faviconTask?.cancel()
        faviconTask = nil
        faviconURL = url
        sidebar.setFavicon(nil)
        guard let url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        if let image = faviconImages[url] {
            sidebar.setFavicon(image)
            return
        }

        let session = faviconSession
        faviconTask = Task { @MainActor [weak self] in
            var request = URLRequest(url: url, timeoutInterval: 5)
            request.attribution = .user
            guard let (data, response) = try? await session.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  !Task.isCancelled, let self, self.faviconURL == url,
                  let image = NSImage(data: data) else { return }
            self.faviconImages[url] = image
            self.sidebar.setFavicon(image)
        }
    }

    deinit {
        timer?.invalidate()
        requestTask?.cancel()
        faviconTask?.cancel()
    }
}

/// A drawn cursor that acts out the agent's current action over the page snapshot. It never takes input.
@MainActor
private final class PIRAgentOverlayView: NSView {
    private enum HighlightStyle {
        case working
        case attention
    }

    private let canvas = CALayer()
    private let pageOutline = CAShapeLayer()
    private let cursor = CALayer()
    private let arrow = CAShapeLayer()
    private let labelPill = CAShapeLayer()
    private let labelIcon = CALayer()
    private let labelText = CATextLayer()
    private let ripple = CAShapeLayer()
    private let labelFont = NSFont.systemFont(ofSize: 11, weight: .bold)
    private var highlights: [CAShapeLayer] = []
    private var typedFields: [CATextLayer] = []
    private var highlightedIndexes: [Int] = []
    private var highlightStyle = HighlightStyle.working
    private var pageOutlineStyle: HighlightStyle?
    private var target: PIRLivePreviewTarget?
    private var imageSize = CGSize.zero
    private var choreography: Task<Void, Never>?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        canvas.isGeometryFlipped = true
        layer?.addSublayer(canvas)

        pageOutline.fillColor = nil
        pageOutline.lineWidth = 4
        pageOutline.opacity = 0
        canvas.addSublayer(pageOutline)

        ripple.fillColor = nil
        ripple.lineWidth = 2
        ripple.opacity = 0
        ripple.bounds = CGRect(x: 0, y: 0, width: 36, height: 36)
        ripple.path = CGPath(ellipseIn: ripple.bounds, transform: nil)
        canvas.addSublayer(ripple)

        // The macOS arrow, translated so its tip sits on the cursor layer's origin.
        let path = CGMutablePath()
        path.addLines(between: [CGPoint(x: 0, y: 0), CGPoint(x: 3.5, y: 14.5), CGPoint(x: 6.3, y: 10.2),
                                CGPoint(x: 10.8, y: 14.9), CGPoint(x: 12.7, y: 13), CGPoint(x: 8.2, y: 8.4),
                                CGPoint(x: 13.1, y: 7.3)])
        path.closeSubpath()
        arrow.path = path
        arrow.lineWidth = 1.4
        arrow.lineJoin = .round
        arrow.shadowOpacity = 0.3
        arrow.shadowRadius = 1.5
        arrow.shadowOffset = CGSize(width: 0, height: 1)
        cursor.addSublayer(arrow)

        labelIcon.contents = DesignSystemImages.Glyphs.Size24.duckDuckGoDaxColor
        labelIcon.contentsGravity = .resizeAspect
        labelPill.addSublayer(labelIcon)
        labelText.font = labelFont
        labelText.fontSize = labelFont.pointSize
        labelText.alignmentMode = .left
        labelPill.addSublayer(labelText)
        cursor.addSublayer(labelPill)
        cursor.anchorPoint = .zero
        cursor.bounds = .zero
        cursor.opacity = 0
        canvas.addSublayer(cursor)
        applyColors()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        canvas.frame = bounds
        drawPageOutline()
        drawHighlights()
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        labelText.contentsScale = window?.backingScaleFactor ?? 2
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    func update(target: PIRLivePreviewTarget?, imageSize: CGSize, needsAssistance: Bool, isManualControl: Bool) {
        self.imageSize = imageSize
        if isManualControl || needsAssistance {
            stopActing()
            // Point at the widget that needs a person when the page shows one; otherwise outline the whole page.
            self.target = needsAssistance ? target : nil
            let widget = elementRect(0)
            highlight(widget == nil ? [] : [0], style: .attention)
            pageOutlineStyle = widget != nil ? nil : needsAssistance ? .attention : .working
            drawPageOutline()
            if needsAssistance {
                let page = imageRect
                let point = widget.map { CGPoint(x: min($0.maxX + 12, page.maxX - 24), y: $0.midY) } ?? CGPoint(x: page.midX, y: page.midY)
                moveCursor(to: point, label: "Waiting for you", opacity: 0.6, duration: 0.45)
            } else {
                hideCursor()
            }
            return
        }

        pageOutlineStyle = nil
        drawPageOutline()
        guard let target else {
            stopActing()
            hideCursor()
            return
        }
        let isNewAction = target.actionID != self.target?.actionID
        self.target = target
        if isNewAction {
            act(on: target)
        } else {
            drawHighlights()
        }
    }

    func reset() {
        stopActing()
        pageOutlineStyle = nil
        drawPageOutline()
        hideCursor()
    }

    // MARK: - Choreography

    private func act(on target: PIRLivePreviewTarget) {
        choreography?.cancel()
        clearTypedFields()
        choreography = Task { @MainActor [weak self] in
            guard let self else { return }
            switch target.actionType {
            case .fillForm: await self.fillFields(texts: target.texts, count: target.rects.count)
            case .click: await self.click()
            case .extract: self.readResults(count: target.rects.count)
            case .getCaptchaInfo, .solveCaptcha: self.solveCaptcha()
            default: break
            }
        }
    }

    private func fillFields(texts: [String?], count: Int) async {
        for index in 0..<count {
            guard let field = elementRect(index) else { continue }
            highlight([index], style: .working)
            let inset = min(Self.typedTextInset, field.width / 2)
            moveCursor(to: CGPoint(x: field.minX + inset, y: field.midY), label: "Moving", duration: 0.35)
            guard await wait(0.35), let field = elementRect(index) else { return }
            guard let text = texts.indices.contains(index) ? texts[index] : nil, !text.isEmpty else {
                let typedWidth = max(inset, min(field.width - inset, field.width * 0.6))
                moveCursor(to: CGPoint(x: field.minX + typedWidth, y: field.midY), label: "Typing", duration: 0.55, timing: .linear)
                guard await wait(0.55) else { return }
                continue
            }
            // CCF sets every value at once afterwards, so type the profile value here for the snapshot to catch up to.
            let layer = typedField(in: field)
            let font = NSFont.systemFont(ofSize: layer.fontSize)
            setLabel("Typing")
            for length in 1...text.count {
                let typed = String(text.prefix(length))
                let typedWidth = (typed as NSString).size(withAttributes: [.font: font]).width
                // Same transaction, no animation, so the cursor sits on the character just typed.
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                layer.string = typed
                cursor.position = CGPoint(x: min(field.maxX - 2, field.minX + inset + typedWidth), y: field.midY)
                CATransaction.commit()
                guard await wait(0.05) else { return }
            }
        }
        // By now the real values are in the page; let the next snapshot show them.
        guard await wait(1) else { return }
        clearTypedFields()
    }

    private static let typedTextInset: CGFloat = 4

    private func typedField(in field: CGRect) -> CATextLayer {
        let layer = CATextLayer()
        layer.fontSize = max(8, min(13, field.height * 0.5))
        layer.font = NSFont.systemFont(ofSize: layer.fontSize)
        layer.contentsScale = window?.backingScaleFactor ?? 2
        layer.truncationMode = .end
        // Stands in for the broker's own white input, covering its placeholder text while we type.
        layer.backgroundColor = NSColor.white.cgColor
        layer.foregroundColor = NSColor.black.cgColor
        let lineHeight = ceil(layer.fontSize * 1.3)
        let inset = min(Self.typedTextInset, field.width / 2)
        layer.frame = CGRect(x: field.minX + inset, y: field.midY - lineHeight / 2, width: max(0, field.width - inset * 2), height: lineHeight)
        canvas.insertSublayer(layer, below: ripple)
        typedFields.append(layer)
        return layer
    }

    private func clearTypedFields() {
        typedFields.forEach { $0.removeFromSuperlayer() }
        typedFields = []
    }

    private func click() async {
        guard let button = elementRect(0) else { return }
        highlight([0], style: .working)
        moveCursor(to: CGPoint(x: button.midX, y: button.midY), label: "Moving", duration: 0.45)
        guard await wait(0.6), let button = elementRect(0) else { return }
        let point = CGPoint(x: button.midX, y: button.midY)
        moveCursor(to: point, label: "Clicking", duration: 0.1)
        press(at: point)
    }

    private func readResults(count: Int) {
        highlight(Array(0..<count), style: .working)
        guard let first = elementRect(0) else { return }
        moveCursor(to: CGPoint(x: first.minX + min(16, first.width / 2), y: first.minY + min(16, first.height / 2)),
                   label: "Reading results", duration: 0.45)
    }

    private func solveCaptcha() {
        highlight([0], style: .attention)
        guard let captcha = elementRect(0) else { return }
        moveCursor(to: CGPoint(x: captcha.midX, y: captcha.midY), label: "Solving the security check", duration: 0.45)
    }

    private func stopActing() {
        choreography?.cancel()
        choreography = nil
        target = nil
        clearTypedFields()
        highlight([], style: .working)
    }

    private func wait(_ seconds: TimeInterval) async -> Bool {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        return !Task.isCancelled
    }

    // MARK: - Drawing

    private var reducesMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    private var imageRect: CGRect {
        guard imageSize.width > 0, imageSize.height > 0, bounds.width > 0, bounds.height > 0 else { return bounds }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
    }

    /// Maps a viewport-fraction rect onto the snapshot, dropping elements scrolled out of view.
    private func elementRect(_ index: Int) -> CGRect? {
        guard let rects = target?.rects, rects.indices.contains(index) else { return nil }
        let page = imageRect
        let fraction = rects[index]
        let rect = CGRect(x: page.minX + fraction.minX * page.width, y: page.minY + fraction.minY * page.height,
                          width: fraction.width * page.width, height: fraction.height * page.height).intersection(page)
        return rect.isNull || rect.width < 1 || rect.height < 1 ? nil : rect
    }

    private func highlight(_ indexes: [Int], style: HighlightStyle) {
        highlightedIndexes = indexes
        highlightStyle = style
        drawHighlights()
    }

    private func drawHighlights() {
        let rects = highlightedIndexes.compactMap(elementRect)
        while highlights.count < rects.count {
            let layer = CAShapeLayer()
            layer.lineWidth = 2
            canvas.insertSublayer(layer, below: ripple)
            highlights.append(layer)
        }
        while highlights.count > rects.count {
            highlights.removeLast().removeFromSuperlayer()
        }
        for (layer, rect) in zip(highlights, rects) {
            layer.path = CGPath(roundedRect: rect.insetBy(dx: -3, dy: -3), cornerWidth: 5, cornerHeight: 5, transform: nil)
        }
        applyHighlightColors()
    }

    private func drawPageOutline() {
        let page = imageRect.insetBy(dx: 2, dy: 2)
        pageOutline.path = CGPath(roundedRect: page, cornerWidth: 10, cornerHeight: 10, transform: nil)
        pageOutline.opacity = pageOutlineStyle == nil ? 0 : 1
        applyColors()
    }

    private func moveCursor(to point: CGPoint, label: String, opacity: Float = 1, duration: TimeInterval,
                            timing: CAMediaTimingFunctionName = .easeInEaseOut) {
        if cursor.opacity == 0 {
            // Enter from the page center so the first move reads as motion.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let page = imageRect
            cursor.position = CGPoint(x: page.midX, y: page.midY)
            CATransaction.commit()
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(reducesMotion ? 0 : duration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: timing))
        cursor.position = point
        cursor.opacity = opacity
        CATransaction.commit()
        setLabel(label)
    }

    private func hideCursor() {
        cursor.opacity = 0
    }

    private func setLabel(_ label: String) {
        guard labelText.string as? String != label else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let size = (label as NSString).size(withAttributes: [.font: labelFont])
        let height: CGFloat = 22
        labelPill.frame = CGRect(x: 18, y: 14, width: ceil(size.width) + 32, height: height)
        labelPill.path = Self.pillPath(labelPill.bounds)
        labelIcon.frame = CGRect(x: 3, y: 3, width: 16, height: 16)
        labelText.frame = CGRect(x: 22, y: (height - ceil(size.height)) / 2, width: ceil(size.width) + 1, height: ceil(size.height))
        labelText.string = label
        CATransaction.commit()
    }

    /// A pill whose nearly square top-leading corner points back at the cursor tip.
    private static func pillPath(_ rect: CGRect) -> CGPath {
        let radius = rect.height / 2
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX + 2, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.maxY), radius: radius)
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY), radius: radius)
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.minY), radius: radius)
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY), radius: 2)
        path.closeSubpath()
        return path
    }

    private func press(at point: CGPoint) {
        guard !reducesMotion else { return }
        let squeeze = CABasicAnimation(keyPath: "transform.scale")
        squeeze.fromValue = 1
        squeeze.toValue = 0.82
        squeeze.duration = 0.12
        squeeze.autoreverses = true
        arrow.add(squeeze, forKey: "press")

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ripple.position = point
        CATransaction.commit()
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.3
        grow.toValue = 1.5
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.9
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [grow, fade]
        group.duration = 0.5
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        ripple.add(group, forKey: "ripple")
    }

    private func applyColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            arrow.fillColor = NSColor.black.cgColor
            arrow.strokeColor = NSColor.white.cgColor
            labelPill.fillColor = NSColor.controlAccentColor.cgColor
            labelText.foregroundColor = NSColor.white.cgColor
            ripple.strokeColor = NSColor.controlAccentColor.cgColor
            pageOutline.strokeColor = (pageOutlineStyle == .attention ? NSColor.systemOrange : NSColor.controlAccentColor).cgColor
        }
        applyHighlightColors()
    }

    private func applyHighlightColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let color = highlightStyle == .attention ? NSColor.systemOrange : NSColor.controlAccentColor
            for layer in highlights {
                layer.strokeColor = color.cgColor
                layer.fillColor = color.withAlphaComponent(0.12).cgColor
            }
        }
    }
}

/// The page's address and what DuckDuckGo is doing on it, like the bar above a browser tab.
@MainActor
private final class PIRBrowserBarView: NSView {
    private let lock = NSImageView(image: DesignSystemImages.Glyphs.Size16.lock)
    private let address = NSTextField(labelWithString: "")
    private let dax = NSImageView(image: DesignSystemImages.Glyphs.Size24.duckDuckGoDaxColor)
    private let status = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        lock.contentTintColor = .secondaryLabelColor
        address.lineBreakMode = .byTruncatingTail
        address.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        dax.imageScaling = .scaleProportionallyUpOrDown
        status.lineBreakMode = .byTruncatingTail
        let leading = NSStackView(views: [lock, address])
        leading.spacing = 6
        let trailing = NSStackView(views: [dax, status])
        trailing.spacing = 6
        for stack in [leading, trailing] {
            stack.alignment = .centerY
            stack.translatesAutoresizingMaskIntoConstraints = false
            addSubview(stack)
        }
        trailing.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            lock.widthAnchor.constraint(equalToConstant: 14),
            lock.heightAnchor.constraint(equalToConstant: 14),
            dax.widthAnchor.constraint(equalToConstant: 16),
            dax.heightAnchor.constraint(equalToConstant: 16),
            leading.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            leading.centerYAnchor.constraint(equalTo: centerYAnchor),
            trailing.leadingAnchor.constraint(greaterThanOrEqualTo: leading.trailingAnchor, constant: 12),
            trailing.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            trailing.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        reset()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.cornerRadius = 10
        layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    func update(pageURL: URL?, brokerName: String, isOptOut: Bool, needsAssistance: Bool, isManualControl: Bool) {
        let host = pageURL?.host.map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 }
        let text = NSMutableAttributedString(string: host ?? "Opening \(brokerName)\u{2026}",
                                             attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.labelColor])
        if let path = pageURL?.path, host != nil, path.count > 1 {
            text.append(NSAttributedString(string: " " + path,
                                           attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor]))
        }
        address.attributedStringValue = text
        lock.isHidden = pageURL?.scheme != "https"

        let state = isManualControl ? "you have control" : needsAssistance ? "is waiting for you" : isOptOut ? "is filling this in" : "is searching"
        let statusText = NSMutableAttributedString(string: "DuckDuckGo ",
                                                   attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.labelColor])
        statusText.append(NSAttributedString(string: state, attributes: [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: needsAssistance ? NSColor.systemOrange : NSColor.secondaryLabelColor
        ]))
        status.attributedStringValue = statusText
    }

    func reset() {
        address.stringValue = ""
        lock.isHidden = true
        status.stringValue = ""
    }
}

/// Lists the current step's actions so the user can see where the agent is.
@MainActor
private final class PIRStepsSidebarView: NSView {
    private struct State: Equatable {
        let brokerName: String
        let checklist: PIRLivePreviewChecklist?
        let needsAssistance: Bool
        let isManualControl: Bool
    }

    private let width: CGFloat
    private let headerCard = SidebarHeaderCard()
    private let favicon = NSImageView()
    private let titleLabel = NSTextField(wrappingLabelWithString: "")
    private let subtitleLabel = NSTextField(wrappingLabelWithString: "")
    private let steps = NSStackView()
    private let stepsScroll = NSScrollView()
    private let footer = NSStackView()
    private let placeholderIcon = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
    private var state: State?

    init(width: CGFloat) {
        self.width = width
        super.init(frame: .zero)

        favicon.imageScaling = .scaleProportionallyUpOrDown
        favicon.wantsLayer = true
        favicon.layer?.cornerRadius = 24
        favicon.layer?.masksToBounds = true
        favicon.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 19, weight: .medium)
        titleLabel.alignment = .center
        titleLabel.preferredMaxLayoutWidth = width - 40
        subtitleLabel.font = .systemFont(ofSize: 14)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.alignment = .center
        subtitleLabel.preferredMaxLayoutWidth = width - 40
        let headerContent = NSStackView(views: [favicon, titleLabel, subtitleLabel])
        headerContent.orientation = .vertical
        headerContent.alignment = .centerX
        headerContent.spacing = 8
        headerContent.setCustomSpacing(16, after: favicon)
        headerContent.translatesAutoresizingMaskIntoConstraints = false
        headerCard.addSubview(headerContent)

        steps.orientation = .vertical
        steps.alignment = .leading
        steps.spacing = 14
        steps.translatesAutoresizingMaskIntoConstraints = false
        // Long steps, such as SpyFly's scan, scroll instead of running past the footer.
        let stepsDocument = FlippedView()
        stepsDocument.translatesAutoresizingMaskIntoConstraints = false
        stepsDocument.addSubview(steps)
        stepsScroll.documentView = stepsDocument
        stepsScroll.drawsBackground = false
        stepsScroll.hasVerticalScroller = true
        stepsScroll.autohidesScrollers = true
        stepsScroll.translatesAutoresizingMaskIntoConstraints = false
        footer.orientation = .horizontal
        footer.translatesAutoresizingMaskIntoConstraints = false
        headerCard.translatesAutoresizingMaskIntoConstraints = false
        // The header keeps its full height; the steps below scroll instead.
        for view in [headerContent, titleLabel, subtitleLabel] as [NSView] {
            view.setContentCompressionResistancePriority(.required, for: .vertical)
        }
        addSubview(headerCard)
        addSubview(stepsScroll)
        addSubview(footer)

        NSLayoutConstraint.activate([
            favicon.widthAnchor.constraint(equalToConstant: 48),
            favicon.heightAnchor.constraint(equalToConstant: 48),
            headerContent.topAnchor.constraint(equalTo: headerCard.topAnchor, constant: 28),
            headerContent.leadingAnchor.constraint(equalTo: headerCard.leadingAnchor, constant: 20),
            headerContent.trailingAnchor.constraint(equalTo: headerCard.trailingAnchor, constant: -20),
            headerContent.bottomAnchor.constraint(equalTo: headerCard.bottomAnchor, constant: -20),
            headerCard.topAnchor.constraint(equalTo: topAnchor),
            headerCard.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerCard.trailingAnchor.constraint(equalTo: trailingAnchor),
            stepsScroll.topAnchor.constraint(equalTo: headerCard.bottomAnchor, constant: 12),
            stepsScroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            stepsScroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            stepsScroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -12),
            stepsDocument.topAnchor.constraint(equalTo: stepsScroll.contentView.topAnchor),
            stepsDocument.leadingAnchor.constraint(equalTo: stepsScroll.contentView.leadingAnchor),
            stepsDocument.widthAnchor.constraint(equalTo: stepsScroll.contentView.widthAnchor),
            steps.topAnchor.constraint(equalTo: stepsDocument.topAnchor, constant: 8),
            steps.leadingAnchor.constraint(equalTo: stepsDocument.leadingAnchor, constant: 12),
            steps.trailingAnchor.constraint(equalTo: stepsDocument.trailingAnchor, constant: -12),
            steps.bottomAnchor.constraint(equalTo: stepsDocument.bottomAnchor, constant: -8),
            footer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            footer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])
        reset()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setFooter(_ view: NSView) {
        footer.addArrangedSubview(view)
    }

    func setFavicon(_ image: NSImage?) {
        favicon.image = image ?? placeholderIcon
        favicon.contentTintColor = image == nil ? .controlAccentColor : nil
    }

    func showNotice(_ notice: String) {
        subtitleLabel.stringValue = notice
        state = nil
    }

    func update(brokerName: String, checklist: PIRLivePreviewChecklist?, needsAssistance: Bool, isManualControl: Bool) {
        let state = State(brokerName: brokerName, checklist: checklist, needsAssistance: needsAssistance, isManualControl: isManualControl)
        guard state != self.state else { return }
        self.state = state

        let isOptOut = checklist?.isOptOut == true
        let isConfirmation = checklist?.isConfirmation == true
        titleLabel.stringValue = isConfirmation ? "Confirming your removal from \(brokerName)"
            : isOptOut ? "Removing you from \(brokerName)" : "Looking for you on \(brokerName)"
        if isManualControl {
            subtitleLabel.stringValue = "You have control. We\u{2019}ll pick up once the page is clear."
        } else if needsAssistance {
            subtitleLabel.stringValue = "We\u{2019}ve paused. \(brokerName) needs a person for the next step."
        } else if isConfirmation {
            subtitleLabel.stringValue = "\(brokerName) emailed a confirmation link. We\u{2019}re following it to finish your request."
        } else {
            subtitleLabel.stringValue = isOptOut ? "We\u{2019}re filling in \(brokerName)\u{2019}s form for you. You\u{2019}ll only need to step in if it asks for a person."
                : "We\u{2019}re checking whether \(brokerName) has a record of you."
        }

        steps.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard let checklist else { return }
        var focus: NSView?
        for (index, item) in checklist.items.enumerated() {
            let phase: StepRow.Phase = index < checklist.currentIndex ? .done
                : index > checklist.currentIndex ? .pending
                : needsAssistance || isManualControl ? .waiting : .current
            let row = StepRow(title: item, phase: phase, width: width - 24)
            steps.addArrangedSubview(row)
            if index == checklist.currentIndex { focus = row }
            if phase == .waiting {
                // The "Your turn" box is its own checklist item, right after the step that needs the user.
                let callout = YourTurnCallout(width: width - 24)
                steps.addArrangedSubview(callout)
                callout.widthAnchor.constraint(equalToConstant: width - 24).isActive = true
                focus = callout
            }
        }
        layoutSubtreeIfNeeded()
        if let focus {
            focus.scrollToVisible(focus.bounds.insetBy(dx: 0, dy: -24))
        }
    }

    func reset(message: String? = nil) {
        state = nil
        setFavicon(nil)
        titleLabel.stringValue = "Personal Information Removal"
        subtitleLabel.stringValue = message ?? "We\u{2019}ll show each broker here while we work on it."
        steps.arrangedSubviews.forEach { $0.removeFromSuperview() }
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
private final class SidebarHeaderCard: NSView {
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.cornerRadius = 16
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.04).cgColor
    }
}

@MainActor
private final class StepRow: NSStackView {
    enum Phase {
        case done
        case current
        case waiting
        case pending
    }

    init(title: String, phase: Phase, width: CGFloat) {
        super.init(frame: .zero)
        orientation = .horizontal
        alignment = .centerY
        spacing = 12

        let indicator: NSView
        if phase == .done {
            let image = NSImageView(image: DesignSystemImages.Glyphs.Size16.checkCircle)
            image.contentTintColor = .controlAccentColor
            indicator = image
        } else {
            indicator = StepRing(phase: phase)
        }
        indicator.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            indicator.widthAnchor.constraint(equalToConstant: 20),
            indicator.heightAnchor.constraint(equalToConstant: 20)
        ])

        let label = NSTextField(wrappingLabelWithString: title)
        label.font = .systemFont(ofSize: 14, weight: phase == .current || phase == .waiting ? .semibold : .regular)
        label.textColor = phase == .pending ? .secondaryLabelColor : .labelColor
        label.preferredMaxLayoutWidth = width - 32
        addArrangedSubview(indicator)
        addArrangedSubview(label)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
private final class StepRing: NSView {
    private let phase: StepRow.Phase

    init(phase: StepRow.Phase) {
        self.phase = phase
        super.init(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 1.5, dy: 1.5))
        ring.lineWidth = 1.5
        switch phase {
        case .pending:
            NSColor.tertiaryLabelColor.setStroke()
            ring.stroke()
        case .current, .waiting:
            let color = phase == .waiting ? NSColor.systemOrange : NSColor.controlAccentColor
            color.setStroke()
            ring.stroke()
            color.setFill()
            NSBezierPath(ovalIn: bounds.insetBy(dx: 6, dy: 6)).fill()
        case .done:
            break
        }
    }
}

/// Tells the user what to do while the agent waits on them.
@MainActor
private final class YourTurnCallout: NSView {
    init(width: CGFloat) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.borderWidth = 1.5

        let title = NSTextField(labelWithString: "Your turn")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        let body = NSTextField(wrappingLabelWithString: "Choose Take Control and complete the security check. We\u{2019}ll continue as soon as it clears.")
        body.font = .systemFont(ofSize: 12)
        body.textColor = .secondaryLabelColor
        body.preferredMaxLayoutWidth = width - 28
        let content = NSStackView(views: [title, body])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 4
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.1).cgColor
        layer?.borderColor = NSColor.systemOrange.withAlphaComponent(0.6).cgColor
    }
}

private final class PreviewCardView: NSVisualEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard alphaValue > 0, super.hitTest(point) != nil else { return nil }
        let hit = super.hitTest(point)
        if hit is NSButton { return hit }
        // Let the steps list scroll; everything else stays inert.
        var ancestor = hit
        while let view = ancestor {
            if view is NSScrollView { return hit }
            ancestor = view.superview
        }
        return self
    }

    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func rightMouseUp(with event: NSEvent) {}
    override func otherMouseDown(with event: NSEvent) {}
    override func otherMouseUp(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}
}
#endif
