//
//  ActionViewController.swift
//  AskDuckAIAction
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

import Common
import UIKit
import Core
import UniformTypeIdentifiers
import os.log

private extension CharacterSet {

    /// Unreserved characters only, so `&`, `=`, `+` and friends in a shared prompt cannot alter the deep link's structure.
    static let askQueryValueAllowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+?#/;,:$@!*'()"))
}

/// Copy owned by the extension bundle, which cannot reach the app's `UserText`.
private enum ExtensionUserText {

    static let fileTooLarge = NSLocalizedString(
        "share.error.fileTooLarge",
        bundle: Bundle(for: ActionViewController.self),
        value: "This file is too large to share to Duck.ai",
        comment: "Shown in the Ask Duck.ai share sheet when the shared file exceeds the size limit"
    )
}

class ActionViewController: UIViewController {

    private enum Constants {
        static let maximumInlineURLLength = 1500
        static let source = "shareExtension"
        static let defaultMIMEType = "application/octet-stream"
        static let openURLSelector = "openURL:"
        static let loadingDeadline: TimeInterval = 10
        static let messageDuration: TimeInterval = 1.8
        static let dimAlpha: CGFloat = 0.3
        static let cardCornerRadius: CGFloat = 14
        static let cardMinimumSide: CGFloat = 120
        static let cardPadding: CGFloat = 24
        static let cardSpacing: CGFloat = 16
        static let cardMaximumWidthRatio: CGFloat = 0.7
    }

    private enum LoadedItem {
        case text(String)
        case url(URL)
        case file(url: URL, kind: AIChatSharePayload.Item.Kind, mimeType: String)
    }

    /// Outcome of staging a single provider's bytes, so an oversized item can be dropped without
    /// falling through to the in-memory fallback that would read it anyway.
    private enum StagingResult {
        case staged(URL)
        case tooLarge
        case failed
    }

    /// Collects provider results behind a lock so the loading deadline and the last provider
    /// completion race safely: whichever arrives first claims the items, the other gets nothing.
    private final class LoadingState {

        private let lock = NSLock()
        private var results = [Int: LoadedItem]()
        private var hasClaimed = false

        func store(_ item: LoadedItem, at index: Int) {
            lock.lock()
            results[index] = item
            lock.unlock()
        }

        /// The items loaded so far, once. Every later call returns nil, so routing runs exactly once.
        func claimItems() -> [LoadedItem]? {
            lock.lock()
            defer { lock.unlock() }
            guard !hasClaimed else { return nil }
            hasClaimed = true
            return results.sorted { $0.key < $1.key }.map { $0.value }
        }
    }

    private let cardView = UIView()
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let messageLabel = UILabel()

    private let oversizedLock = NSLock()
    private var didSkipOversizedItem = false

    private var hasStarted = false
    private var hasFinished = false

    override func viewDidLoad() {
        super.viewDidLoad()
        configureLoadingView()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        guard !hasStarted else { return }
        hasStarted = true

        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        guard !providers.isEmpty else {
            done()
            return
        }

        load(providers: providers) { [weak self] items in
            self?.handle(items: items)
        }
    }

    // MARK: - Loading view

    private func configureLoadingView() {
        view.backgroundColor = UIColor.black.withAlphaComponent(Constants.dimAlpha)

        cardView.backgroundColor = .systemBackground
        cardView.layer.cornerRadius = Constants.cardCornerRadius
        cardView.layer.cornerCurve = .continuous
        cardView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cardView)

        activityIndicator.color = .secondaryLabel
        activityIndicator.startAnimating()

        messageLabel.font = .preferredFont(forTextStyle: .subheadline)
        messageLabel.textColor = .label
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.isHidden = true

        let stackView = UIStackView(arrangedSubviews: [activityIndicator, messageLabel])
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = Constants.cardSpacing
        stackView.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(stackView)

        NSLayoutConstraint.activate([
            cardView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            cardView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            cardView.widthAnchor.constraint(greaterThanOrEqualToConstant: Constants.cardMinimumSide),
            cardView.heightAnchor.constraint(greaterThanOrEqualToConstant: Constants.cardMinimumSide),
            cardView.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: Constants.cardMaximumWidthRatio),
            stackView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: Constants.cardPadding),
            stackView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -Constants.cardPadding),
            stackView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: Constants.cardPadding),
            stackView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -Constants.cardPadding)
        ])
    }

    /// Replaces the spinner with a short message, then finishes on its own.
    private func showMessageThenFinish(_ message: String) {
        activityIndicator.stopAnimating()
        activityIndicator.isHidden = true
        messageLabel.text = message
        messageLabel.isHidden = false

        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.messageDuration) { [weak self] in
            self?.done()
        }
    }

    // MARK: - Loading

    private func load(providers: [NSItemProvider], completion: @escaping ([LoadedItem]) -> Void) {
        let state = LoadingState()
        let group = DispatchGroup()

        for (index, provider) in providers.enumerated() {
            group.enter()
            load(provider: provider) { item in
                if let item {
                    state.store(item, at: index)
                }
                group.leave()
            }
        }

        let deliver = {
            guard let items = state.claimItems() else { return }
            completion(items)
        }

        group.notify(queue: .main, execute: deliver)
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.loadingDeadline, execute: deliver)
    }

    private func load(provider: NSItemProvider, completion: @escaping (LoadedItem?) -> Void) {
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            let identifier = preferredTypeIdentifier(for: provider, conformingTo: .image) ?? UTType.image.identifier
            loadFile(provider: provider, typeIdentifier: identifier, kind: .image, completion: completion)
            return
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            // Prefer a concrete registered type so the bytes arrive with their real extension. Falling
            // back to a file representation of `public.file-url` would stage the URL string itself,
            // since that identifier conforms to `public.data`.
            if let concrete = preferredTypeIdentifier(for: provider, conformingTo: .data),
               UTType(concrete)?.conforms(to: .url) == false {
                loadFile(provider: provider, typeIdentifier: concrete, kind: .file, completion: completion)
            } else {
                loadFileURL(provider: provider, completion: completion)
            }
            return
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                guard let url = item as? URL, !url.isFileURL else {
                    completion(nil)
                    return
                }
                completion(.url(url))
            }
            return
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                guard let text = item as? String else {
                    completion(nil)
                    return
                }
                completion(.text(text))
            }
            return
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { item, _ in
                if let text = item as? String {
                    completion(.text(text))
                } else if let data = item as? Data, let text = String(data: data, encoding: .utf8) {
                    completion(.text(text))
                } else {
                    completion(nil)
                }
            }
            return
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.data.identifier) {
            let identifier = preferredTypeIdentifier(for: provider, conformingTo: .data) ?? UTType.data.identifier
            loadFile(provider: provider, typeIdentifier: identifier, kind: .file, completion: completion)
            return
        }

        completion(nil)
    }

    /// The most specific registered identifier conforming to `type`, so staged files keep a usable extension and MIME type.
    private func preferredTypeIdentifier(for provider: NSItemProvider, conformingTo type: UTType) -> String? {
        let candidates = provider.registeredTypeIdentifiers.compactMap { UTType($0) }.filter { $0.conforms(to: type) }
        if let concrete = candidates.first(where: { $0 != type && $0.preferredFilenameExtension != nil }) {
            return concrete.identifier
        }
        return candidates.first?.identifier
    }

    private func loadFile(provider: NSItemProvider,
                          typeIdentifier: String,
                          kind: AIChatSharePayload.Item.Kind,
                          completion: @escaping (LoadedItem?) -> Void) {

        provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { [weak self] url, _ in
            guard let self else {
                completion(nil)
                return
            }
            guard let url else {
                self.loadDataFallback(provider: provider, typeIdentifier: typeIdentifier, kind: kind, completion: completion)
                return
            }

            switch self.stage(fileAt: url) {
            case .staged(let staged):
                completion(.file(url: staged, kind: kind, mimeType: self.mimeType(for: staged, typeIdentifier: typeIdentifier)))
            case .tooLarge:
                completion(nil)
            case .failed:
                self.loadDataFallback(provider: provider, typeIdentifier: typeIdentifier, kind: kind, completion: completion)
            }
        }
    }

    /// Resolves a `public.file-url` provider through `loadItem`, which yields the referenced file's
    /// URL rather than a representation of the URL string.
    private func loadFileURL(provider: NSItemProvider, completion: @escaping (LoadedItem?) -> Void) {
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] item, _ in
            guard let self else {
                completion(nil)
                return
            }

            let resolved: URL?
            if let url = item as? URL {
                resolved = url
            } else if let data = item as? Data {
                resolved = URL(dataRepresentation: data, relativeTo: nil)
            } else {
                resolved = nil
            }

            guard let resolved, resolved.isFileURL else {
                self.loadDataFallback(provider: provider,
                                      typeIdentifier: UTType.data.identifier,
                                      kind: .file,
                                      completion: completion)
                return
            }

            switch self.stage(fileAt: resolved) {
            case .staged(let staged):
                completion(.file(url: staged, kind: .file, mimeType: self.mimeType(for: staged, typeIdentifier: UTType.data.identifier)))
            case .tooLarge:
                completion(nil)
            case .failed:
                self.loadDataFallback(provider: provider,
                                      typeIdentifier: UTType.data.identifier,
                                      kind: .file,
                                      completion: completion)
            }
        }
    }

    private func loadDataFallback(provider: NSItemProvider,
                                  typeIdentifier: String,
                                  kind: AIChatSharePayload.Item.Kind,
                                  completion: @escaping (LoadedItem?) -> Void) {

        provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { [weak self] item, _ in
            guard let self else {
                completion(nil)
                return
            }

            if let url = item as? URL, url.isFileURL {
                switch self.stage(fileAt: url) {
                case .staged(let staged):
                    completion(.file(url: staged, kind: kind, mimeType: self.mimeType(for: staged, typeIdentifier: typeIdentifier)))
                    return
                case .tooLarge:
                    completion(nil)
                    return
                case .failed:
                    break
                }
            }

            if let data = item as? Data {
                let fileExtension = UTType(typeIdentifier)?.preferredFilenameExtension ?? "dat"
                switch self.stage(data: data, fileExtension: fileExtension) {
                case .staged(let staged):
                    completion(.file(url: staged, kind: kind, mimeType: self.mimeType(for: staged, typeIdentifier: typeIdentifier)))
                    return
                case .tooLarge:
                    completion(nil)
                    return
                case .failed:
                    break
                }
            }

            if let image = item as? UIImage, let data = image.pngData() {
                switch self.stage(data: data, fileExtension: "png") {
                case .staged(let staged):
                    completion(.file(url: staged, kind: .image, mimeType: "image/png"))
                    return
                case .tooLarge, .failed:
                    break
                }
            }

            completion(nil)
        }
    }

    // MARK: - Staging

    private func stage(fileAt url: URL) -> StagingResult {
        let hasScopedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasScopedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        if let byteCount = byteCount(ofFileAt: url), byteCount > AIChatShareInbox.maximumItemByteCount {
            noteOversizedItemSkipped()
            return .tooLarge
        }

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(url.lastPathComponent.isEmpty ? UUID().uuidString : url.lastPathComponent)
        do {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: destination)
            return .staged(destination)
        } catch {
            Logger.lifecycle.error("Ask Duck.ai: failed to stage shared file: \(error.localizedDescription, privacy: .public)")
            return .failed
        }
    }

    private func stage(data: Data, fileExtension: String) -> StagingResult {
        guard data.count <= AIChatShareInbox.maximumItemByteCount else {
            noteOversizedItemSkipped()
            return .tooLarge
        }

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("attachment").appendingPathExtension(fileExtension)
        do {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: destination, options: .atomic)
            return .staged(destination)
        } catch {
            Logger.lifecycle.error("Ask Duck.ai: failed to stage shared data: \(error.localizedDescription, privacy: .public)")
            return .failed
        }
    }

    private func byteCount(ofFileAt url: URL) -> Int? {
        if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
            return size
        }
        return (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int
    }

    /// Staging runs on provider callback queues, so the oversized flag is written behind its own lock.
    private func noteOversizedItemSkipped() {
        oversizedLock.lock()
        didSkipOversizedItem = true
        oversizedLock.unlock()
    }

    private var hasSkippedOversizedItem: Bool {
        oversizedLock.lock()
        defer { oversizedLock.unlock() }
        return didSkipOversizedItem
    }

    private func mimeType(for url: URL, typeIdentifier: String) -> String {
        if let type = UTType(filenameExtension: url.pathExtension), let mimeType = type.preferredMIMEType {
            return mimeType
        }
        if let mimeType = UTType(typeIdentifier)?.preferredMIMEType {
            return mimeType
        }
        return Constants.defaultMIMEType
    }

    // MARK: - Routing

    private func handle(items: [LoadedItem]) {
        guard !items.isEmpty else {
            if hasSkippedOversizedItem {
                showMessageThenFinish(ExtensionUserText.fileTooLarge)
            } else {
                done()
            }
            return
        }

        guard isAIChatEnabled else {
            handleDegraded(items: items)
            return
        }

        let prompt = self.prompt(from: items)
        let files = items.compactMap { item -> (url: URL, kind: AIChatSharePayload.Item.Kind, mimeType: String)? in
            guard case .file(let url, let kind, let mimeType) = item else { return nil }
            return (url, kind, mimeType)
        }

        if files.isEmpty, let prompt, let url = inlineURL(prompt: prompt) {
            launch(url: url)
            return
        }

        guard let url = tokenURL(prompt: prompt, files: files) else {
            handleDegraded(items: items)
            return
        }
        launch(url: url)
    }

    private func handleDegraded(items: [LoadedItem]) {
        for item in items {
            switch item {
            case .url(let url):
                launchQuickLink(url: url)
                return
            case .text(let text):
                guard let searchURL = URL.makeSearchURL(text: text) else {
                    Logger.lifecycle.error("Ask Duck.ai: couldn‘t form search URL for shared text")
                    continue
                }
                launchQuickLink(url: searchURL)
                return
            case .file:
                continue
            }
        }
        done()
    }

    private var isAIChatEnabled: Bool {
        let defaults = UserDefaults(suiteName: Global.appConfigurationGroupName)
        guard let value = defaults?.object(forKey: AppConfigurationKeyNames.isAIChatEnabled) as? Bool else {
            return true
        }
        return value
    }

    private func prompt(from items: [LoadedItem]) -> String? {
        let parts = items.compactMap { item -> String? in
            switch item {
            case .text(let text):
                return text.trimmingCharacters(in: .whitespacesAndNewlines)
            case .url(let url):
                return url.absoluteString
            case .file:
                return nil
            }
        }.filter { !$0.isEmpty }

        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "\n")
    }

    private func inlineURL(prompt: String) -> URL? {
        guard let url = askURL(parameterName: "prompt", value: prompt),
              url.absoluteString.count <= Constants.maximumInlineURLLength else {
            return nil
        }
        return url
    }

    /// Builds `ddgOpenAIChat://ask?source=…&<parameterName>=<value>`, encoding the value so reserved characters survive parsing.
    private func askURL(parameterName: String, value: String) -> URL? {
        guard let encoded = value.addingPercentEncoding(withAllowedCharacters: .askQueryValueAllowed) else { return nil }
        let base = AppDeepLinkSchemes.openAIChat.appending("ask")
        return URL(string: "\(base)?source=\(Constants.source)&\(parameterName)=\(encoded)")
    }

    private func tokenURL(prompt: String?, files: [(url: URL, kind: AIChatSharePayload.Item.Kind, mimeType: String)]) -> URL? {
        do {
            let (token, directory) = try AIChatShareInbox.makePayloadDirectory()
            var items = [AIChatSharePayload.Item]()

            for file in files {
                let fileName = file.url.lastPathComponent
                let destination = directory.appendingPathComponent(fileName)
                let finalURL = FileManager.default.fileExists(atPath: destination.path)
                    ? directory.appendingPathComponent("\(UUID().uuidString)-\(fileName)")
                    : destination
                try FileManager.default.moveItem(at: file.url, to: finalURL)
                items.append(AIChatSharePayload.Item(kind: file.kind,
                                                     fileName: finalURL.lastPathComponent,
                                                     mimeType: file.mimeType,
                                                     relativePath: finalURL.lastPathComponent))
            }

            let payload = AIChatSharePayload(prompt: prompt, items: items)
            try AIChatShareInbox.writeManifest(payload, to: directory)

            return askURL(parameterName: "payloadToken", value: token)
        } catch {
            Logger.lifecycle.error("Ask Duck.ai: failed to write share payload: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Launching

    private func launchQuickLink(url: URL) {
        guard let deepLink = URL(string: AppDeepLinkSchemes.quickLink.appending(url.absoluteString)) else {
            done()
            return
        }
        launch(url: deepLink)
    }

    private func launch(url: URL) {
        DispatchQueue.main.async {
            var responder = self as UIResponder?
            let selectorOpenURL = sel_registerName(Constants.openURLSelector)
            while let current = responder {
                if #available(iOS 18.0, *) {
                    if let application = current as? UIApplication {
                        application.open(url, options: [:], completionHandler: nil)
                        break
                    }
                } else {
                    if current.responds(to: selectorOpenURL) {
                        current.perform(selectorOpenURL, with: url, afterDelay: 0)
                        break
                    }
                }
                responder = current.next
            }
            self.done()
        }
    }

    private func done() {
        guard !hasFinished else { return }
        hasFinished = true
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}
