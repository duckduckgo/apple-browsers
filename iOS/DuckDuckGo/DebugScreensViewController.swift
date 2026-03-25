//
//  DebugScreensViewController.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

class DebugScreensViewController: UIHostingController<DebugScreensView> {

    convenience init(dependencies: DebugScreen.Dependencies) {
        let model = DebugScreensViewModel(dependencies: dependencies)
        self.init(rootView: DebugScreensView(model: model))
        model.pushController = { [weak self] in
            self?.navigationController?.pushViewController($0, animated: true)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        rootView.model.refreshToggles()
    }

    @objc func dismissSelf() {
        dismiss(animated: true)
    }

}

struct DebugScreensView: View {

    @ObservedObject var model: DebugScreensViewModel

    var body: some View {
        List {
            if !model.isSearching {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Shake your device or press \u{2303}\u{2318}Z in the Simulator to open this screen quickly.", systemImage: "info.circle")
                        Text("On App Store builds, this screen will only show if you're signed in as an internal user via **use-login.duckduckgo.com**.")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .listRowBackground(Color(designSystemColor: .surface))
                DebugTogglesView(model: model)
                    .listRowBackground(Color(designSystemColor: .surface))

                if !model.pinnedScreens.isEmpty {
                    DebugScreensListView(model: model, sectionTitle: "Pinned", screens: model.pinnedScreens)
                }

                Section {
                    Label("Swipe left on any item below to pin it for quick access.", systemImage: "hand.point.left")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(Color(designSystemColor: .surface))

                DebugScreensListView(model: model, sectionTitle: "Screens", screens: model.unpinnedScreens)
                DebugScreensListView(model: model, sectionTitle: "Actions", screens: model.actions)
            } else if model.filtered.isEmpty && model.filteredFeatureFlags.isEmpty {
                if #available(iOS 17.0, *) {
                    ContentUnavailableView("No Results", systemImage: "magnifyingglass", description: Text("No matches for \"\(model.filter)\""))
                } else {
                    Label("No results for \"\(model.filter)\"", systemImage: "magnifyingglass")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                if !model.filtered.isEmpty {
                    DebugScreensListView(model: model, sectionTitle: "Results", screens: model.filtered)
                }

                if !model.filteredFeatureFlags.isEmpty {
                    Section(header: Text(verbatim: "Feature Flags")) {
                        ForEach(model.filteredFeatureFlags, id: \.self) { flag in
                            HStack {
                                Toggle(
                                    isOn: Binding(
                                        get: { model.isFeatureFlagEnabled(flag) },
                                        set: { _ in model.toggleFeatureFlag(flag) }
                                    )
                                ) {
                                    VStack(alignment: .leading) {
                                        Text(verbatim: flag.rawValue)
                                            .font(.headline)
                                        Text(verbatim: "Default: \(model.featureFlagDefaultValue(flag))")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                }
                                Button(action: {
                                    model.resetFeatureFlagOverride(flag)
                                }, label: {
                                    Text(verbatim: "Reset")
                                        .padding()
                                })
                                .foregroundColor(.blue)
                            }
                        }
                    }
                    .listRowBackground(Color(designSystemColor: .surface))
                }
            }
        }
        .searchable(text: $model.filter, prompt: "Filter")
        .navigationTitle("Debug")
        .applyBackground()
    }
}

struct DebugScreensListView: View {
    
    @ObservedObject var model: DebugScreensViewModel

    let sectionTitle: String
    let screens: [DebugScreen]

    @ViewBuilder
    func togglePinButton(_ screen: DebugScreen) -> some View {
        Button {
            model.togglePin(screen)
        } label: {
            Image(systemName: model.isPinned(screen) ? "pin.slash" : "pin")
        }
    }

    var body: some View {
        Section {
            ForEach(screens) { screen in
                switch screen {
                case .controller(let title, _):
                    SettingsCellView(label: title, action: {
                        model.navigateToController(screen)
                    }, disclosureIndicator: true, isButton: true)
                    .swipeActions {
                        togglePinButton(screen)
                    }

                case .view(let title, _):
                    NavigationLink(destination: LazyView(model.buildView(screen))) {
                        SettingsCellView(
                            label: title
                        )
                    }
                    .swipeActions {
                        togglePinButton(screen)
                    }

                case .action(let title, _):
                    SettingsCellView(label: title, image: Image(systemName: "hammer"), action: {
                        model.executeAction(screen)
                    }, isButton: true)
                    .swipeActions {
                        togglePinButton(screen)
                    }
                }
            }
            .listRowBackground(Color(designSystemColor: .surface))
        } header: {
            Text(verbatim: sectionTitle)
        }
    }

}

// This should be used sparingly.  Don't add some trivial toggle here; please create a new screen.
//  Please only add here if this toggle is going to be frequently used in the long term.
struct DebugTogglesView: View {

    @ObservedObject var model: DebugScreensViewModel

    var body: some View {
        Section {
            Toggle(isOn: $model.isInternalUser) {
                Label {
                    Text(verbatim: "Internal User")
                        .accessibilityIdentifier("Settings.Debug.InternalUser.identifier")
                } icon: {
                    Image(systemName: "flask")
                }
            }

            Toggle(isOn: $model.isInspectibleWebViewsEnabled) {
                Label {
                    Text(verbatim: "Inspectable WebViews")
                } icon: {
                    Image(systemName: "globe")
                }
            }
        }
    }

}
