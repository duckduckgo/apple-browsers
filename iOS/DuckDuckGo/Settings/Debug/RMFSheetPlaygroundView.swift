//
//  RMFSheetPlaygroundView.swift
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

import SwiftUI
import DesignResourcesKitIcons

/// Shows the RMF sheet template with any combination of its parts.
struct RMFSheetPlaygroundView: View {

    enum LabelOption: String, CaseIterable { case none, new, subtle }
    enum ExitOption: String, CaseIterable { case close, secondary, both }
    enum ChoiceOption: String, CaseIterable { case none, two, three }

    @State private var fullHeight = false
    @State private var showMedia = true
    @State private var label: LabelOption = .new
    @State private var title = "Title goes here"
    @State private var showBody = true
    @State private var longBody = false
    @State private var choices: ChoiceOption = .none
    @State private var exit: ExitOption = .both
    @State private var showFootnote = false
    @State private var lastAction = "None"
    @State private var stage: Stage?

    var body: some View {
        List {
            Section("Sheet") {
                OnOffPicker(title: "Full height", isOn: $fullHeight)
                Picker("Close", selection: $exit) {
                    Text("Close button").tag(ExitOption.close)
                    Text("Secondary button").tag(ExitOption.secondary)
                    Text("Both").tag(ExitOption.both)
                }
            }
            Section("Parts") {
                OnOffPicker(title: "Illustration", isOn: $showMedia)
                Picker("Label", selection: $label) {
                    ForEach(LabelOption.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                TextField("Title", text: $title)
                OnOffPicker(title: "Body", isOn: $showBody)
                OnOffPicker(title: "Long body", isOn: $longBody)
                Picker("Choice list", selection: $choices) {
                    ForEach(ChoiceOption.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                OnOffPicker(title: "Footnote", isOn: $showFootnote)
            }
        }
        .accessibilityIdentifier("rmfPlaygroundList")
        .safeAreaInset(edge: .bottom) {
            Text("Last action: \(lastAction)")
                .frame(maxWidth: .infinity)
                .padding()
                .background(.bar)
                .accessibilityIdentifier("rmfPlaygroundLastAction")
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Show", action: showSheet)
                    .accessibilityIdentifier("rmfPlaygroundShowSheet")
            }
        }
        .navigationTitle("RMF Sheet")
        .fullScreenCover(item: $stage) { stage in
            StageView(content: stage.content) { action in
                lastAction = String(describing: action)
                self.stage = nil
            }
            .ignoresSafeArea()
        }
    }

    /// A menu rather than a switch, so UI automation can set it by tapping.
    private struct OnOffPicker: View {
        let title: String
        @Binding var isOn: Bool

        var body: some View {
            Picker(title, selection: $isOn) {
                Text("On").tag(true)
                Text("Off").tag(false)
            }
        }
    }

    private var content: RMFSheetContent {
        let bodyText = longBody
            ? Array(repeating: "Body text explains the benefit in one or two short sentences.", count: 12).joined(separator: " ")
            : "Body text explains the benefit in one or two short sentences."
        let allChoices: [RMFSheetContent.ChoiceList.Choice] = [
            .init(id: "accept", title: "Accept cookies that can't be rejected", description: "Saves you a click on most sites"),
            .init(id: "keep", title: "I'll keep accepting them myself", description: "Nothing changes"),
            .init(id: "third", title: "Option 3", description: nil)
        ]
        let choiceList: RMFSheetContent.ChoiceList? = switch choices {
        case .none: nil
        case .two: .init(choices: Array(allChoices.prefix(2)), preselectedID: "accept")
        case .three: .init(choices: allChoices, preselectedID: "accept")
        }
        let sheetExit: RMFSheetContent.Exit = switch exit {
        case .close: .closeButton
        case .secondary: .secondaryButton("Not now")
        case .both: .closeAndSecondaryButton("Not now")
        }
        let sheetLabel: RMFSheetContent.Label? = switch label {
        case .none: nil
        case .new: .init(text: "New", style: .new)
        case .subtle: .init(text: "Limited time", style: .subtle)
        }
        return RMFSheetContent(
            height: fullHeight ? .full : .content,
            media: showMedia ? Image(uiImage: DesignSystemImages.Color.Size96.cookieCheckFeature) : nil,
            label: sheetLabel,
            title: title,
            body: showBody ? bodyText : nil,
            choiceList: choiceList,
            primaryButtonTitle: "Primary action",
            exit: sheetExit,
            footnote: showFootnote ? "You can change this any time in Settings." : nil
        )
    }

    private func showSheet() {
        stage = Stage(content: content)
    }
}

/// A full-screen backdrop to present from, so an iPad sheet gets the regular-width layout it has over the browser
/// rather than the compact one it would inherit from this Debug form sheet.
private struct Stage: Identifiable {
    let id = UUID()
    let content: RMFSheetContent
}

private struct StageView: UIViewControllerRepresentable {
    let content: RMFSheetContent
    let onAction: (RMFSheetAction) -> Void

    func makeUIViewController(context: Context) -> StageViewController {
        StageViewController(content: content, onAction: onAction)
    }

    func updateUIViewController(_ uiViewController: StageViewController, context: Context) {}
}

private final class StageViewController: UIViewController {
    private let content: RMFSheetContent
    private let onAction: (RMFSheetAction) -> Void
    private var hasPresented = false

    init(content: RMFSheetContent, onAction: @escaping (RMFSheetAction) -> Void) {
        self.content = content
        self.onAction = onAction
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .secondarySystemBackground
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !hasPresented else { return }
        hasPresented = true
        present(RMFSheetViewController(content: content, onAction: onAction), animated: true)
    }
}
