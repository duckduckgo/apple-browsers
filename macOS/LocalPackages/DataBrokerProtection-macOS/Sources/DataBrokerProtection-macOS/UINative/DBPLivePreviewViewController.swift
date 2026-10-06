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

/// A read-only preview of the original page in the PIR background agent.
@MainActor
public final class DBPLivePreviewViewController: NSViewController {
    public init(agentInterface: DataBrokerProtectionAppToAgentInterface, hidesWhenIdle: Bool = true) {
        self.agentInterface = agentInterface
        self.hidesWhenIdle = hidesWhenIdle
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func loadView() {
        // The demo uses a 200pt square snapshot of the agent's square web view.
        let card = PreviewCardView()
        card.material = .popover
        card.blendingMode = .withinWindow
        card.state = .active
        card.wantsLayer = true
        card.layer?.cornerRadius = 16
        card.layer?.masksToBounds = true
        card.alphaValue = hidesWhenIdle ? 0 : 1
        view = card

        icon.image = globeImage
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.contentTintColor = .controlAccentColor
        icon.translatesAutoresizingMaskIntoConstraints = false

        brokerLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        brokerLabel.lineBreakMode = .byTruncatingTail
        activityLabel.font = .systemFont(ofSize: 11)
        activityLabel.textColor = .secondaryLabelColor
        activityLabel.lineBreakMode = .byTruncatingTail
        let labels = NSStackView(views: [brokerLabel, activityLabel])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 4

        let header = NSStackView(views: [icon, labels])
        header.spacing = 10
        header.alignment = .centerY
        header.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.wantsLayer = true
        imageView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        imageView.layer?.cornerRadius = 10
        imageView.layer?.masksToBounds = true
        view.addSubview(imageView)

        placeholderLabel.font = .systemFont(ofSize: 12)
        placeholderLabel.textColor = .secondaryLabelColor
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(placeholderLabel)

        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 24),
            icon.heightAnchor.constraint(equalToConstant: 24),
            header.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            header.heightAnchor.constraint(equalToConstant: 32),
            imageView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            imageView.widthAnchor.constraint(equalToConstant: 200),
            imageView.heightAnchor.constraint(equalToConstant: 200),
            imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            placeholderLabel.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
            placeholderLabel.centerYAnchor.constraint(equalTo: imageView.centerYAnchor)
        ])
    }

    public override func viewDidAppear() {
        super.viewDidAppear()
        guard timer == nil else { return }
        generation = UUID()
        clearFrame(message: "Connecting to PIR agent")
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
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
        clearFrame(message: "No active operation")
    }

    private let agentInterface: DataBrokerProtectionAppToAgentInterface
    private let hidesWhenIdle: Bool
    private let brokerLabel = NSTextField(labelWithString: "PIR activity")
    private let activityLabel = NSTextField(labelWithString: "Connecting to PIR agent")
    private let placeholderLabel = NSTextField(labelWithString: "Waiting for a broker page")
    private let imageView = NSImageView()
    private let icon = NSImageView()
    private let globeImage = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
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
                clearFrame(message: "PIR agent did not respond")
            }
            return
        }

        requestStartedAt = Date()
        let generation = generation
        let agentInterface = agentInterface
        requestTask = Task { @MainActor [weak self] in
            let result: Result<DBPLivePreviewFrame?, Error>
            do {
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
            case .failure: self.clearFrame(message: "Preview unavailable")
            }
        }
    }

    private func display(_ frame: DBPLivePreviewFrame?) {
        guard let frame else {
            clearFrame(message: "No active operation")
            return
        }
        guard let image = NSImage(data: frame.imageData), image.size.width > 0, image.size.height > 0 else {
            clearFrame(message: "Preview unavailable")
            return
        }
        brokerLabel.stringValue = frame.brokerName
        activityLabel.stringValue = frame.activity
        imageView.image = image
        updateFavicon(frame.faviconURL)
        placeholderLabel.isHidden = true
        view.alphaValue = 1
    }

    private func clearFrame(message: String) {
        // Keep polling while the card is transparent so a new operation can reveal it.
        view.alphaValue = hidesWhenIdle ? 0 : 1
        updateFavicon(nil)
        brokerLabel.stringValue = "PIR activity"
        activityLabel.stringValue = message
        imageView.image = nil
        placeholderLabel.stringValue = "Waiting for a broker page"
        placeholderLabel.isHidden = false
    }

    private func updateFavicon(_ url: URL?) {
        guard url != faviconURL else { return }
        faviconTask?.cancel()
        faviconTask = nil
        faviconURL = url
        icon.image = globeImage
        icon.contentTintColor = .controlAccentColor
        guard let url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        if let image = faviconImages[url] {
            icon.image = image
            icon.contentTintColor = nil
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
            self.icon.image = image
            self.icon.contentTintColor = nil
        }
    }

    deinit {
        timer?.invalidate()
        requestTask?.cancel()
        faviconTask?.cancel()
    }
}

private final class PreviewCardView: NSVisualEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard alphaValue > 0, super.hitTest(point) != nil else { return nil }
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
