//
//  BrowserToolsDebugView.swift
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

#if DEBUG || ALPHA
import AIChat
import SwiftUI
import UIKit

private enum BrowserToolsDebugText {
    static let title = "Browser Tools"
    static let tool = "Tool"
    static let arguments = "Arguments (JSON)"
    static let openFullScreen = "Open in Full Screen"
    static let done = "Done"
    static let run = "Run"
    static let response = "Response"
    static let copy = "Copy Response"
    static let clearResponse = "Clear Response"
    static let owner = "Owner"
    static let mode = "Mode"
    static let normal = "Normal"
    static let fire = "Fire"
    static let fireUnsupported = "Browser tools are not supported in Fire mode."
    static let chooseTab = "Choose Tab (copy tabId)"
    static let switchToTabDetails = "Keeps the debug menu open and switches tabs in the background."
    static let noTabs = "No tabs available for switching."
    static let newTab = "New Tab"
    static let unavailable = "Unavailable"
    static let reset = "Reset Browser Tool Permissions"
    static let resetDetails = "Clears saved Always/Never decisions."
    static let invalidJSON = "JSON error"
    static let showMockPrompt = "Show Mock Permission Alert"
    static let mockPromptUnavailable = "Could not show the mock permission alert."
}

struct BrowserToolsDebugView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model: BrowserToolsDebugModel
    @State private var isShowingArgumentsEditor = false
    private let tabManager: TabManager

    init(tabManager: TabManager) {
        self.tabManager = tabManager
        _model = StateObject(wrappedValue: BrowserToolsDebugModel(tabManager: tabManager))
    }

    var body: some View {
        Form {
            Section {
                Text(verbatim: "\(BrowserToolsDebugText.owner): \(model.ownerID ?? BrowserToolsDebugText.unavailable)")
                    .textSelection(.enabled)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "\(BrowserToolsDebugText.mode): \(model.modeDescription)")
                    Text(verbatim: BrowserToolsDebugText.fireUnsupported)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                Picker(selection: $model.tool) {
                    ForEach([ClientToolCapability.listOpenTabs, .switchToTab, .readTabContent, .searchHistory, .findInPage], id: \.name) { capability in
                        Text(verbatim: capability.name).tag(capability.name)
                    }
                } label: {
                    Text(verbatim: BrowserToolsDebugText.tool)
                }
                .disabled(model.isRunning)
                if model.tool == ClientToolCapability.switchToTab.name {
                    Text(verbatim: BrowserToolsDebugText.switchToTabDetails)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            Section(header: Text(verbatim: BrowserToolsDebugText.arguments)) {
                TextEditor(text: $model.arguments)
                    .font(.system(.body, design: .monospaced))
                    .disableAutocorrection(true)
                    .textInputAutocapitalization(.never)
                    .frame(minHeight: 100)
                    .disabled(model.isRunning)
                Button {
                    isShowingArgumentsEditor = true
                } label: {
                    Text(verbatim: BrowserToolsDebugText.openFullScreen)
                }
                .disabled(model.isRunning)
                if model.tool == ClientToolCapability.switchToTab.name {
                    NavigationLink(destination: BrowserToolsDebugTabPicker(tabManager: tabManager)) {
                        Text(verbatim: BrowserToolsDebugText.chooseTab)
                    }
                    .disabled(model.isRunning)
                }
                Button(action: model.run) { Text(verbatim: BrowserToolsDebugText.run) }
                    .disabled(model.isRunning)
                if model.isRunning { SwiftUI.ProgressView() }
            }
            Section {
                Button(action: model.showMockPermissionAlert) { Text(verbatim: BrowserToolsDebugText.showMockPrompt) }
                    .disabled(model.isRunning)
            }
            if let output = model.output {
                Section(header: Text(verbatim: BrowserToolsDebugText.response)) {
                    Text(verbatim: output)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                    Button { UIPasteboard.general.string = output } label: {
                        Text(verbatim: BrowserToolsDebugText.copy)
                    }
                    Button(action: model.clearResponse) {
                        Text(verbatim: BrowserToolsDebugText.clearResponse)
                    }
                }
            }
            Section(footer: Text(verbatim: BrowserToolsDebugText.resetDetails)) {
                Button(role: .destructive, action: model.resetPermissions) { Text(verbatim: BrowserToolsDebugText.reset) }
                    .disabled(model.isRunning)
            }
        }
        .navigationTitle(Text(verbatim: BrowserToolsDebugText.title))
        .onDisappear { model.leaveScreen() }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                model.reopen()
            } else {
                model.close()
            }
        }
        .background(BrowserToolsDebugSurface(model: model).frame(width: 0, height: 0))
        .fullScreenCover(isPresented: $isShowingArgumentsEditor) {
            BrowserToolsDebugArgumentsEditor(arguments: $model.arguments)
        }
    }
}

private struct BrowserToolsDebugArgumentsEditor: View {
    @Binding var arguments: String
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationView {
            TextEditor(text: $arguments)
                .font(.system(.body, design: .monospaced))
                .disableAutocorrection(true)
                .textInputAutocapitalization(.never)
                .focused($isFocused)
                .padding()
                .navigationTitle(Text(verbatim: BrowserToolsDebugText.arguments))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Text(verbatim: BrowserToolsDebugText.done)
                        }
                    }
                }
                .onAppear { isFocused = true }
        }
        .navigationViewStyle(.stack)
    }
}

private struct BrowserToolsDebugTabPicker: View {
    let tabManager: TabManager
    @Environment(\.dismiss) private var dismiss
    @State private var tabs: [Tab] = []

    var body: some View {
        List {
            if tabs.isEmpty {
                Text(verbatim: BrowserToolsDebugText.noTabs)
                    .foregroundColor(.secondary)
            }
            ForEach(tabs, id: \.uid) { tab in
                Button {
                    copyTabID(tab)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: tab.link?.displayTitle ?? BrowserToolsDebugText.newTab)
                        if let url = tab.link?.url {
                            Text(verbatim: url.absoluteString)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                        Text(verbatim: tab.uid)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .foregroundColor(.primary)
            }
        }
        .navigationTitle(Text(verbatim: BrowserToolsDebugText.chooseTab))
        .onReceive(tabManager.normalTabsModel.tabsPublisher) { tabs in
            self.tabs = tabManager.currentBrowsingMode == .normal
                ? tabs.filter { $0.mode == .normal && $0.link?.url.isDuckAIURL != true }
                : []
        }
    }

    private func copyTabID(_ tab: Tab) {
        guard tabManager.currentBrowsingMode == .normal, tab.mode == .normal,
              tab.link?.url.isDuckAIURL != true,
              tabManager.normalTabsModel.tabs.contains(where: { $0 === tab }) else { return }
        UIPasteboard.general.string = tab.uid
        dismiss()
    }
}

@MainActor
private final class BrowserToolsDebugModel: ObservableObject {
    enum Execution {
        case idle
        case running(Task<Void, Never>)
        case finished(String)
    }

    @Published var tool = ClientToolCapability.listOpenTabs.name {
        didSet {
            switch tool {
            case ClientToolCapability.listOpenTabs.name: arguments = "{\"limit\":50}"
            case ClientToolCapability.switchToTab.name: arguments = "{\n  \"tabId\": \"\"\n}"
            case ClientToolCapability.searchHistory.name: arguments = "{\"limit\":10}"
            case ClientToolCapability.findInPage.name: arguments = "{\"query\":\"\",\"maxMatches\":10}"
            default: arguments = "{}"
            }
        }
    }
    @Published var arguments = "{\"limit\":50}"
    @Published private var execution = Execution.idle
    let ownerID: String?
    private let tabManager: TabManager
    private weak var owner: Tab?
    private weak var surface: UIViewController?
    private var session: BrowserToolsDebugSession?
    private var mockPermissionPresenter: AIChatToolPermissionPresenter?

    init(tabManager: TabManager) {
        self.tabManager = tabManager
        let owner = tabManager.currentTabsModel.currentTab
        self.owner = owner
        self.ownerID = owner?.uid
    }

    var isRunning: Bool {
        if case .running = execution { return true }
        return false
    }

    var output: String? {
        if case .finished(let output) = execution { return output }
        return nil
    }

    var modeDescription: String {
        tabManager.currentBrowsingMode == .normal ? BrowserToolsDebugText.normal : BrowserToolsDebugText.fire
    }

    func open(surface: UIViewController) {
        self.surface = surface
        guard session == nil else { return }
        guard let owner, let scope = tabManager.makeBrowserToolScope(for: owner) else { return }
        let presenter = AIChatToolPermissionPresenter { [weak surface] in
            guard let surface, surface.viewIfLoaded?.window?.windowScene?.activationState == .foregroundActive else { return nil }
            return .init(surface)
        }
        session = BrowserToolsDebugSession(service: tabManager.browserToolsService, scope: scope, presenter: presenter,
                                          isNormalMode: { [weak tabManager] in tabManager?.currentBrowsingMode == .normal })
    }

    func reopen() {
        guard let surface, surface.viewIfLoaded?.window != nil else { return }
        open(surface: surface)
    }

    func close() {
        mockPermissionPresenter?.withdrawActive {}
        mockPermissionPresenter = nil
        if case .running(let task) = execution { task.cancel() }
        session?.close()
        session = nil
        if isRunning { execution = .idle }
    }

    func leaveScreen() {
        surface = nil
        close()
    }

    func showMockPermissionAlert() {
        guard let surface, !isRunning, mockPermissionPresenter?.isPresentingPermission != true else { return }
        let presenter = AIChatToolPermissionPresenter { [weak surface] in
            surface.map { .init($0) }
        }
        let tools: [ClientToolCapability] = [.readTabContent, .searchHistory, .listOpenTabs]
        // Repeat the sample tools to exercise scrolling in the permission list.
        guard presenter.previewAccessPrompt(toolNames: (tools + tools).map(\.name)) else {
            execution = .finished(BrowserToolsDebugText.mockPromptUnavailable)
            return
        }
        mockPermissionPresenter = presenter
    }

    func resetPermissions() {
        tabManager.browserToolsService.permissions.clearAll()
    }

    func clearResponse() {
        guard case .finished = execution else { return }
        execution = .idle
    }

    func run() {
        guard !isRunning else { return }
        let request: ExecuteClientToolRequest
        do {
            let input = try JSONDecoder().decode(JSONValue.self, from: Data(arguments.utf8))
            let payload: JSONValue = ["callId": .string(UUID().uuidString),
                                      "capability": ["name": .string(tool), "version": 1], "input": input]
            let raw = try JSONSerialization.jsonObject(with: JSONEncoder().encode(payload))
            guard let parsed = ExecuteClientToolRequest.parse(rawParams: raw) else {
                finish(ExecuteClientToolResponse.invalidRequest(rawParams: raw))
                return
            }
            request = parsed
        } catch {
            execution = .finished("\(BrowserToolsDebugText.invalidJSON): \(error.localizedDescription)")
            return
        }
        guard let session else {
            finish(.failure(callId: request.callId, error: .unavailable))
            return
        }
        execution = .running(Task { [weak self, session, service = tabManager.browserToolsService] in
            let response = await service.invoke(request, from: session)
            guard !Task.isCancelled, let self, self.session === session else { return }
            self.finish(response)
        })
    }

    private func finish(_ response: ExecuteClientToolResponse) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(response.limitedToResultBytes())
            execution = .finished(String(bytes: data, encoding: .utf8) ?? "")
        } catch {
            execution = .finished(error.localizedDescription)
        }
    }
}

private struct BrowserToolsDebugSurface: UIViewControllerRepresentable {
    let model: BrowserToolsDebugModel

    func makeUIViewController(context: Context) -> Surface {
        Surface(model: model)
    }

    func updateUIViewController(_ uiViewController: Surface, context: Context) { }

    static func dismantleUIViewController(_ uiViewController: Surface, coordinator: ()) {
        uiViewController.removeKeyboardDismissalGesture()
        uiViewController.model.leaveScreen()
    }

    final class Surface: UIViewController, UIGestureRecognizerDelegate {
        let model: BrowserToolsDebugModel
        private lazy var keyboardDismissalGesture: UITapGestureRecognizer = {
            let gesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
            gesture.cancelsTouchesInView = false
            gesture.delegate = self
            return gesture
        }()

        init(model: BrowserToolsDebugModel) {
            self.model = model
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            parent?.view.addGestureRecognizer(keyboardDismissalGesture)
            model.open(surface: self)
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            dismissKeyboard()
            removeKeyboardDismissalGesture()
            model.leaveScreen()
        }

        func removeKeyboardDismissalGesture() {
            keyboardDismissalGesture.view?.removeGestureRecognizer(keyboardDismissalGesture)
        }

        @objc private func dismissKeyboard() {
            keyboardDismissalGesture.view?.endEditing(true)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var touchedView = touch.view
            while let view = touchedView {
                if let textView = view as? UITextView, textView.isEditable { return false }
                touchedView = view.superview
            }
            return true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
#endif
