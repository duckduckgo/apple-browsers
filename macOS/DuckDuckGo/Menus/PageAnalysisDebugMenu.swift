//
//  PageAnalysisDebugMenu.swift
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

#if DEBUG && compiler(>=6.4) && canImport(FoundationModels)
import AppKit
import DesignResourcesKit
import FoundationModels
import os.log
import WebKit

/// The checked-in demo files are also bundled, so testing does not depend on checkout paths.
enum PageAnalysisDemo {
    static func resource(_ name: String, extension fileExtension: String) throws -> URL {
        guard let url = Bundle.main.url(forResource: name, withExtension: fileExtension, subdirectory: "PageAnalysisPrototype") else {
            throw PageAnalysisPIRValidationError.message("Missing bundled demo resource: \(name).\(fileExtension). Rebuild the macOS app.")
        }
        return url
    }

    static func json(_ name: String) throws -> String {
        try String(contentsOf: resource(name, extension: "json"), encoding: .utf8)
    }
}

@available(macOS 27.0, *)
@MainActor
final class PageAnalysisDebugMenu: NSMenu {
    private let webViewProvider: () -> WKWebView?
    private let openDemoPage: (URL) -> Void
    private var inspector: PageAnalysisWindowController?

    init(webViewProvider: @escaping () -> WKWebView?, openDemoPage: @escaping (URL) -> Void) {
        self.webViewProvider = webViewProvider
        self.openDemoPage = openDemoPage
        super.init(title: "On-Device Page Analysis")
        let demoItem = NSMenuItem(title: "Open PIR Recovery Demo…", action: #selector(openDemo), keyEquivalent: "p")
        demoItem.keyEquivalentModifierMask = [.command, .option, .control, .shift]
        demoItem.target = self
        addItem(demoItem)
        addItem(.separator())
        let item = NSMenuItem(title: "Analyze Current Tab…", action: #selector(openInspector), keyEquivalent: "p")
        item.keyEquivalentModifierMask = [.command, .option, .control]
        item.target = self
        addItem(item)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func openDemo() {
        do {
            let url = try PageAnalysisDemo.resource("pir-demo", extension: "html")
            if inspector == nil {
                inspector = PageAnalysisWindowController(webViewProvider: webViewProvider)
            }
            try inspector?.loadDemoInputs()
            openDemoPage(url)
            openInspector()
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    @objc private func openInspector() {
        if inspector == nil {
            inspector = PageAnalysisWindowController(webViewProvider: webViewProvider)
        }
        inspector?.showWindow(nil)
        inspector?.window?.makeKeyAndOrderFront(nil)
    }
}

/// Owns one cancellable PIR generation and its in-memory result. All WebKit and UI access stays on the main actor.
@available(macOS 27.0, *)
@MainActor
private final class PageAnalysisWindowController: NSWindowController, NSWindowDelegate {
    private let webViewProvider: () -> WKWebView?
    private let analyzeButton = NSButton(title: "Generate next action", target: nil, action: nil)
    private let contextView = NSTextView()
    private let runtimeView = NSTextView()
    private let captureView = NSTextView()
    private let diagnosticsView = NSTextView()
    private let inputTabs = NSTabView()
    private let resultTabs = NSTabView()
    private let inputSelector = NSSegmentedControl(labels: ["Broker JSON", "Runner state", "Page DOM"], trackingMode: .selectOne, target: nil, action: nil)
    private let resultSelector = NSSegmentedControl(labels: ["Next action", "Diagnostics"], trackingMode: .selectOne, target: nil, action: nil)
    private let inputCaption = NSTextField(wrappingLabelWithString: "Existing PIR recipe. Edit a broker or a single step.")
    private let resultCaption = NSTextField(wrappingLabelWithString: "One proposed PIR action. Nothing is executed.")
    private let copyInputButton = NSButton(title: "Copy", target: nil, action: nil)
    private let copyResultButton = NSButton(title: "Copy", target: nil, action: nil)
    private let progressIndicator = NSProgressIndicator()
    private var hasOutput = false
    private var hasCapture = false
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private let statusLabel = NSTextField(wrappingLabelWithString: "Ready. Use Debug → On-Device Page Analysis → Open PIR Recovery Demo… to load the example.")
    private let outputView = NSTextView()
    private var analysisTask: Task<Void, Never>?
    private var requestID: UUID?
    private static let contentWorld = WKContentWorld.world(name: "DuckDuckGo.Debug.PageAnalysis")
    private static let logger = Logger(subsystem: "com.duckduckgo.macos.browser", category: "PageAnalysis")

    init(webViewProvider: @escaping () -> WKWebView?) {
        self.webViewProvider = webViewProvider
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 760),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "PIR Recovery — On-Device Prototype"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 880, height: 560)
        super.init(window: window)
        window.delegate = self
        configureContent(in: window)
        window.center()
        do {
            try loadDemoInputs()
        } catch {
            statusLabel.stringValue = error.localizedDescription
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureContent(in window: NSWindow) {
        analyzeButton.target = self
        analyzeButton.action = #selector(analyze)
        analyzeButton.bezelStyle = .rounded
        analyzeButton.keyEquivalent = "\r"
        cancelButton.target = self
        cancelButton.action = #selector(cancel)
        cancelButton.isHidden = true
        outputView.string = "The generated action will appear here."
        captureView.string = "Generate an action to capture the current page."
        diagnosticsView.string = "Generation and validation details will appear here."

        let title = NSTextField(labelWithString: "PIR Automated Recovery")
        title.font = .systemFont(ofSize: 24, weight: .semibold)
        let subtitle = NSTextField(labelWithString: "Apple Foundation Models Prototype")
        subtitle.textColor = NSColor(designSystemColor: .textSecondary)
        let heading = NSStackView(views: [title, subtitle])
        heading.orientation = .vertical
        heading.alignment = .leading
        heading.spacing = 4
        let header = NSStackView(views: [heading, NSView(), cancelButton, analyzeButton])
        header.orientation = .horizontal
        header.spacing = 12

        inputSelector.target = self
        inputSelector.action = #selector(selectInput)
        resultSelector.target = self
        resultSelector.action = #selector(selectResult)
        copyInputButton.target = self
        copyInputButton.action = #selector(copyInput)
        copyResultButton.target = self
        copyResultButton.action = #selector(copyResult)
        addTab("broker", textView: contextView, editable: true, to: inputTabs)
        addTab("runtime", textView: runtimeView, editable: true, to: inputTabs)
        addTab("capture", textView: captureView, editable: false, to: inputTabs)
        addTab("action", textView: outputView, editable: false, to: resultTabs)
        addTab("diagnostics", textView: diagnosticsView, editable: false, to: resultTabs)
        inputSelector.selectedSegment = 0
        resultSelector.selectedSegment = 0
        selectInput()
        selectResult()
        let input = makePanel(title: "INPUT", selector: inputSelector, caption: inputCaption, tabs: inputTabs, copyButton: copyInputButton)
        let result = makePanel(title: "OUTPUT", selector: resultSelector, caption: resultCaption, tabs: resultTabs, copyButton: copyResultButton)
        let columns = NSStackView(views: [input, result])
        columns.orientation = .horizontal
        columns.distribution = .fillEqually
        columns.alignment = .top
        columns.spacing = 20

        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isDisplayedWhenStopped = false
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = NSColor(designSystemColor: .textSecondary)
        let footer = NSStackView(views: [progressIndicator, statusLabel, NSView()])
        footer.orientation = .horizontal
        footer.spacing = 8
        let stack = NSStackView(views: [header, columns, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        guard let contentView = window.contentView else { return }
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 22),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            columns.widthAnchor.constraint(equalTo: stack.widthAnchor),
            input.heightAnchor.constraint(equalTo: columns.heightAnchor),
            result.heightAnchor.constraint(equalTo: columns.heightAnchor),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    func loadDemoInputs() throws {
        let broker = try PageAnalysisDemo.json("pir-demo-broker")
        let progress = try PageAnalysisDemo.json("pir-demo-progress")
        cancel()
        contextView.string = broker
        runtimeView.string = progress
        outputView.string = "The generated action will appear here."
        captureView.string = "Generate an action to capture the current page."
        diagnosticsView.string = "Generation and validation details will appear here."
        hasOutput = false
        hasCapture = false
        inputSelector.selectedSegment = 0
        resultSelector.selectedSegment = 0
        selectInput()
        selectResult()
        statusLabel.stringValue = "Demo inputs loaded. Once the page loads, choose Generate next action."
    }

    private func addTab(_ identifier: String, textView: NSTextView, editable: Bool, to tabs: NSTabView) {
        textView.isEditable = editable
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = NSColor(designSystemColor: .textPrimary)
        textView.backgroundColor = NSColor(designSystemColor: .surfacePrimary)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 14, height: 14)
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        scroll.documentView = textView
        let item = NSTabViewItem(identifier: identifier)
        item.view = scroll
        tabs.tabViewType = .noTabsNoBorder
        tabs.addTabViewItem(item)
    }

    private func makePanel(title: String, selector: NSSegmentedControl, caption: NSTextField,
                           tabs: NSTabView, copyButton: NSButton) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = NSColor(designSystemColor: .textSecondary)
        copyButton.bezelStyle = .rounded
        copyButton.controlSize = .small
        let heading = NSStackView(views: [label, NSView(), copyButton])
        heading.orientation = .horizontal
        caption.font = .systemFont(ofSize: 12)
        caption.textColor = NSColor(designSystemColor: .textSecondary)
        caption.maximumNumberOfLines = 2
        let panel = NSStackView(views: [heading, selector, caption, tabs])
        panel.orientation = .vertical
        panel.alignment = .leading
        panel.spacing = 10
        tabs.setContentHuggingPriority(.defaultLow, for: .vertical)
        NSLayoutConstraint.activate([
            heading.widthAnchor.constraint(equalTo: panel.widthAnchor),
            selector.widthAnchor.constraint(equalTo: panel.widthAnchor),
            caption.widthAnchor.constraint(equalTo: panel.widthAnchor),
            caption.heightAnchor.constraint(equalToConstant: 30),
            tabs.widthAnchor.constraint(equalTo: panel.widthAnchor),
            tabs.heightAnchor.constraint(greaterThanOrEqualToConstant: 260)
        ])
        return panel
    }

    @objc private func selectInput() {
        let index = inputSelector.selectedSegment
        inputTabs.selectTabViewItem(at: index)
        let captions = ["Existing PIR recipe. Edit a broker or a single step.",
                        "Execution cursor and available bindings. Values stay outside the model.",
                        "DOM evidence from this run. Input values are omitted."]
        inputCaption.stringValue = captions[index]
        copyInputButton.isEnabled = index != 2 || hasCapture
    }

    @objc private func selectResult() {
        let index = resultSelector.selectedSegment
        resultTabs.selectTabViewItem(at: index)
        resultCaption.stringValue = index == 0 ? "One proposed PIR action. Nothing is executed." : "Model attempts, validation, and the exact instructions and request."
        copyResultButton.isEnabled = index == 0 ? hasOutput : hasCapture
    }

    @objc private func copyInput() {
        let text = [contextView, runtimeView, captureView][inputSelector.selectedSegment].string
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc private func copyResult() {
        let text = resultSelector.selectedSegment == 0 ? outputView.string : diagnosticsView.string
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc private func analyze() {
        cancel()
        hasOutput = false
        hasCapture = false
        outputView.string = "The generated action will appear here."
        captureView.string = "Waiting for a new page capture…"
        diagnosticsView.string = "Waiting for generation…"
        resultSelector.selectedSegment = 0
        selectInput()
        selectResult()
        guard let webView = webViewProvider(), let url = webView.url,
              ["https", "http", "file"].contains(url.scheme?.lowercased() ?? ""), !webView.isLoading else {
            statusLabel.stringValue = "Select a loaded web page in a browser window first."
            return
        }
        let context: PageAnalysisPIRContext
        do {
            context = try PageAnalysisPIRContext(json: contextView.string, runtimeJSON: runtimeView.string)
            try PageAnalysisPIRActionBuilder.validateInput(context)
        } catch {
            statusLabel.stringValue = error.localizedDescription
            return
        }
        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            statusLabel.stringValue = "On-device model unavailable: \(model.availability). Check Apple Intelligence in System Settings."
            return
        }
        let identifier = UUID()
        requestID = identifier
        outputView.string = "Generating the next action…"
        captureView.string = "Capturing the current page…"
        diagnosticsView.string = "Preparing model input…"
        hasOutput = false
        hasCapture = false
        selectInput()
        selectResult()
        setBusy(true)
        statusLabel.stringValue = "Capturing the current page…"
        Self.logger.notice("[PageAnalysis] run=\(identifier.uuidString, privacy: .public) started")
        analysisTask = Task { [weak self, weak webView] in
            guard let self else { return }
            guard let webView else {
                self.cancel()
                self.statusLabel.stringValue = "The tab closed before capture. Select a loaded page and try again."
                return
            }
            await self.performAnalysis(webView: webView, url: url, model: model, context: context, identifier: identifier)
        }
    }

    private func performAnalysis(webView: WKWebView, url: URL, model: SystemLanguageModel,
                                 context: PageAnalysisPIRContext, identifier: UUID) async {
        defer {
            if self.requestID == identifier {
                self.setBusy(false)
                self.analysisTask = nil
                self.requestID = nil
            }
        }
        do {
            try Task.checkCancellation()
            var snapshot = try await runPhase("DOM capture", identifier: identifier) {
                let value = try await webView.evaluateJavaScript(PageAnalysisSnapshot.script, in: nil, contentWorld: Self.contentWorld)
                guard let json = value as? String else { throw AnalysisError.message("Could not capture this page.") }
                return try JSONDecoder().decode(PageAnalysisSnapshot.self, from: Data(json.utf8))
            }
            captureView.string = try snapshot.json()
            hasCapture = true
            selectInput()
            selectResult()
            let modelInstructions = Instructions(PageAnalysisPIRPrompt.instructions)
            let instructionTokens = try await runPhase("Instruction token count", identifier: identifier) {
                try await model.tokenCount(for: modelInstructions)
            }
            let schemaTokens = try await runPhase("Schema token count", identifier: identifier) {
                try await model.tokenCount(for: PageAnalysisPIRProposal.generationSchema)
            }
            let inputBudget = model.contextSize - instructionTokens - schemaTokens
                - PageAnalysisPIRPrompt.maximumResponseTokens - PageAnalysisPIRPrompt.contextReserveTokens
            var textPrompt = Prompt(try PageAnalysisPIRPrompt.request(snapshot: snapshot, context: context))
            var inputTokens = try await runPhase("DOM text token count", identifier: identifier) {
                try await model.tokenCount(for: textPrompt)
            }
            while inputTokens > inputBudget && !snapshot.elements.isEmpty {
                try Task.checkCancellation()
                snapshot.elements.removeLast(min(10, snapshot.elements.count))
                textPrompt = Prompt(try PageAnalysisPIRPrompt.request(snapshot: snapshot, context: context))
                inputTokens = try await runPhase("DOM text token count", identifier: identifier) {
                    try await model.tokenCount(for: textPrompt)
                }
            }
            guard inputTokens <= inputBudget else {
                throw AnalysisError.message("The PIR context exceeds the model window. Supply a shorter action sequence.")
            }
            try Task.checkCancellation()
            guard self.requestID == identifier else { return }
            let evidence = try snapshot.json()
            Self.logger.notice("[PageAnalysis] run=\(identifier.uuidString, privacy: .public) budget instructions=\(instructionTokens) schema=\(schemaTokens) prompt=\(inputTokens) context=\(model.contextSize) elements=\(snapshot.elements.count)")
            self.captureView.string = evidence
            self.diagnosticsView.string = "ANALYSIS INPUT\n\(evidence)"
            let rendered = try await self.generateNextAction(webView: webView, url: url, snapshot: snapshot, context: context,
                                                        model: model, inputBudget: inputBudget, identifier: identifier)
            try Task.checkCancellation()
            try await runPhase("Document validation after inference", identifier: identifier) {
                try await self.validateDocument(webView, url: url, timeOrigin: snapshot.documentTimeOrigin)
            }
            guard self.requestID == identifier else { return }
            self.outputView.string = rendered
            self.outputView.scrollToBeginningOfDocument(nil)
            self.hasOutput = true
            self.selectResult()
            self.statusLabel.stringValue = "Finished · \(snapshot.title). Generate again after changing the page or inputs."
            Self.logger.notice("[PageAnalysis] run=\(identifier.uuidString, privacy: .public) completed")
        } catch {
            guard self.requestID == identifier, !Task.isCancelled else { return }
            self.outputView.string = "No action generated.\n\n\(error.localizedDescription)"
            self.hasOutput = true
            self.selectResult()
            self.diagnosticsView.string += "\n\nERROR\n\(error.localizedDescription)"
            self.statusLabel.stringValue = "Generation failed. See the output for details."
        }
    }

    private func runPhase<Value>(_ phase: String, identifier: UUID, operation: () async throws -> Value) async throws -> Value {
        try Task.checkCancellation()
        let started = ContinuousClock.now
        statusLabel.stringValue = "\(phase)…"
        Self.logger.notice("[PageAnalysis] run=\(identifier.uuidString, privacy: .public) phase=\(phase, privacy: .public) started")
        do {
            let value = try await operation()
            try Task.checkCancellation()
            let elapsed = String(describing: started.duration(to: .now))
            Self.logger.notice("[PageAnalysis] run=\(identifier.uuidString, privacy: .public) phase=\(phase, privacy: .public) completed elapsed=\(elapsed, privacy: .public)")
            return value
        } catch {
            try Task.checkCancellation()
            let nsError = error as NSError
            // Error messages can embed page text. Log only the domain/code; show details in the inspector.
            Self.logger.error("[PageAnalysis] run=\(identifier.uuidString, privacy: .public) phase=\(phase, privacy: .public) failed domain=\(nsError.domain, privacy: .public) code=\(nsError.code)")
            throw AnalysisError.message("\(phase): \(error.localizedDescription)")
        }
    }

    private func generateNextAction(webView: WKWebView, url: URL, snapshot: PageAnalysisSnapshot, context: PageAnalysisPIRContext,
                                    model: SystemLanguageModel, inputBudget: Int,
                                    identifier: UUID) async throws -> String {
        var feedback: String?
        var attempts: [String] = []
        var nextAction = "No action emitted."
        for attempt in 1...2 {
            try await validateDocument(webView, url: url, timeOrigin: snapshot.documentTimeOrigin)
            // Retry in a fresh session so the first transcript does not consume the remaining context.
            let request = try PageAnalysisPIRPrompt.request(snapshot: snapshot, context: context, feedback: feedback)
            let prompt = Prompt(request)
            let promptDiagnostics = "MODEL INSTRUCTIONS\n\(PageAnalysisPIRPrompt.instructions)\n\nMODEL REQUEST\n\(request)"
            diagnosticsView.string = (attempts + [promptDiagnostics]).joined(separator: "\n\n")
            let tokens = try await runPhase("PIR attempt token count", identifier: identifier) {
                try await model.tokenCount(for: prompt)
            }
            guard tokens <= inputBudget else {
                diagnosticsView.string += "\n\nRetry skipped: validation feedback exceeds the remaining input budget."
                break
            }
            let session = LanguageModelSession(model: model, instructions: Instructions(PageAnalysisPIRPrompt.instructions))
            let response = try await runPhase("PIR next-action generation (attempt \(attempt))", identifier: identifier) {
                try await session.respond(to: prompt, generating: PageAnalysisPIRProposal.self,
                                          options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: PageAnalysisPIRPrompt.maximumResponseTokens))
            }
            Self.logger.notice("[PageAnalysis] run=\(identifier.uuidString, privacy: .public) actualInputTokens=\(response.usage.input.totalTokenCount) actualOutputTokens=\(response.usage.output.totalTokenCount)")
            try await validateDocument(webView, url: url, timeOrigin: snapshot.documentTimeOrigin)
            let preview = try await runPhase("PIR action validation", identifier: identifier) {
                try await self.validateProposal(response.content, snapshot: snapshot, context: context, webView: webView)
            }
            nextAction = try preview.action?.json() ?? "No action emitted (\(preview.status.rawValue)).\n\(preview.reason)\n\(preview.validation)"
            attempts.append("ATTEMPT \(attempt)\n" + (try preview.json()))
            // Preserve the first rejection even if the repair is canceled or fails.
            diagnosticsView.string = "PIR DRY RUN — NOTHING EXECUTED\n\n" + (attempts + [promptDiagnostics]).joined(separator: "\n\n")
            guard attempt == 1, preview.status == .rejected else { break }
            do {
                if response.content.kind == .configuredAction {
                    _ = try PageAnalysisPIRActionBuilder.configuredPayload(response.content, context: context)
                } else {
                    _ = try PageAnalysisPIRActionBuilder.validate(response.content, snapshot: snapshot, context: context)
                }
                break // Live target changed or PIR decoding failed: retrying stale evidence cannot fix that.
            } catch {
                feedback = "Rejected kind=\(response.content.kind), elementID=\(response.content.elementID.prefix(30)), "
                    + "binding=\(response.content.binding), configuredActionID=\(response.content.configuredActionID.prefix(60)): "
                    + String(error.localizedDescription.prefix(240))
                    + " Choose a different eligible candidate or pause. Do not repeat the rejected action."
            }
        }
        return nextAction
    }

    private func validateProposal(_ proposal: PageAnalysisPIRProposal, snapshot: PageAnalysisSnapshot,
                                  context: PageAnalysisPIRContext, webView: WKWebView) async throws -> PageAnalysisPIRPreview {
        guard proposal.kind == .fillForm || proposal.kind == .click else {
            return PageAnalysisPIRActionBuilder.preview(proposal, snapshot: snapshot, context: context, target: nil)
        }
        do {
            _ = try PageAnalysisPIRActionBuilder.validate(proposal, snapshot: snapshot, context: context)
            let script = try PageAnalysisSnapshot.targetValidationScript(captureID: snapshot.captureID, elementID: proposal.elementID)
            let value = try await webView.evaluateJavaScript(script, in: nil, contentWorld: Self.contentWorld)
            guard let json = value as? String else {
                throw PageAnalysisPIRValidationError.message("The captured document or target expired. Analyze again.")
            }
            let target = try JSONDecoder().decode(PageAnalysisPIRActionBuilder.Target.self, from: Data(json.utf8))
            return PageAnalysisPIRActionBuilder.preview(proposal, snapshot: snapshot, context: context, target: target)
        } catch {
            try Task.checkCancellation()
            return PageAnalysisPIRActionBuilder.preview(proposal, snapshot: snapshot, context: context,
                                                            target: nil, rejection: error.localizedDescription)
        }
    }

    private func validateDocument(_ webView: WKWebView, url: URL, timeOrigin: Double) async throws {
        try Task.checkCancellation()
        let currentTimeOrigin = try await webView.evaluateJavaScript("performance.timeOrigin", in: nil, contentWorld: Self.contentWorld) as? Double
        guard !webView.isLoading, webView.url == url, currentTimeOrigin == timeOrigin else {
            throw AnalysisError.message("The page navigated during analysis. Analyze it again.")
        }
    }

    @objc private func cancel() {
        if let requestID {
            Self.logger.notice("[PageAnalysis] run=\(requestID.uuidString, privacy: .public) canceled")
        }
        requestID = nil
        analysisTask?.cancel()
        analysisTask = nil
        setBusy(false)
        statusLabel.stringValue = "Canceled."
    }

    private func setBusy(_ busy: Bool) {
        analyzeButton.isEnabled = !busy
        cancelButton.isEnabled = busy
        cancelButton.isHidden = !busy
        if busy { progressIndicator.startAnimation(nil) } else { progressIndicator.stopAnimation(nil) }
        contextView.isEditable = !busy
        runtimeView.isEditable = !busy
    }

    func windowWillClose(_ notification: Notification) {
        cancel()
        outputView.string = ""
        captureView.string = ""
        diagnosticsView.string = ""
        hasOutput = false
        hasCapture = false
        selectInput()
        selectResult()
    }

    private enum AnalysisError: LocalizedError {
        case message(String)

        var errorDescription: String? {
            switch self {
            case .message(let message): return message
            }
        }
    }
}
#endif
