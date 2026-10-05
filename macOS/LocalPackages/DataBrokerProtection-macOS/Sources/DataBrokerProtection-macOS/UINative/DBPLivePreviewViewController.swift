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
    public init(agentInterface: DataBrokerProtectionAppToAgentInterface) {
        self.agentInterface = agentInterface
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func loadView() {
        // Muse-inspired compact card: a 56pt header and a 220pt page preview.
        let card = PreviewCardView()
        card.material = .popover
        card.blendingMode = .withinWindow
        card.state = .active
        card.wantsLayer = true
        card.layer?.cornerRadius = 16
        card.layer?.masksToBounds = true
        view = card

        let icon = NSImageView(image: NSImage(systemSymbolName: "globe", accessibilityDescription: nil) ?? NSImage())
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
            imageView.heightAnchor.constraint(equalToConstant: 220),
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
    private let brokerLabel = NSTextField(labelWithString: "PIR activity")
    private let activityLabel = NSTextField(labelWithString: "Connecting to PIR agent")
    private let placeholderLabel = NSTextField(labelWithString: "Waiting for a broker page")
    private let imageView = NSImageView()
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
        guard let image = NSImage(data: frame.imageData) else {
            clearFrame(message: "Preview unavailable")
            return
        }
        brokerLabel.stringValue = frame.brokerName
        activityLabel.stringValue = frame.activity
        imageView.image = image
        placeholderLabel.isHidden = true
    }

    private func clearFrame(message: String) {
        brokerLabel.stringValue = "PIR activity"
        activityLabel.stringValue = message
        imageView.image = nil
        placeholderLabel.stringValue = "Waiting for a broker page"
        placeholderLabel.isHidden = false
    }

    deinit {
        timer?.invalidate()
        requestTask?.cancel()
    }
}

private final class PreviewCardView: NSVisualEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
#endif
