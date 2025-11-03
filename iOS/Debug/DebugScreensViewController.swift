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

public class DebugScreensViewController: UIHostingController<DebugScreensView> {

    public convenience init(dependencies: AnyDebugDependencies) {
        let model = DebugScreensViewModel(dependencies: dependencies)
        self.init(rootView: DebugScreensView(model: model))
        model.pushController = { [weak self] in
            self?.navigationController?.pushViewController($0, animated: true)
        }
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        rootView.model.refreshToggles()
    }

}

public struct DebugScreensView: View {

    @ObservedObject var model: DebugScreensViewModel

    public var body: some View {
        List {
            if model.filtered.isEmpty {
                DebugTogglesView(model: model)
                    .listRowBackground(Color(designSystemColor: .surface))

                if !model.pinnedScreens.isEmpty {
                    DebugScreensListView(model: model, sectionTitle: "Pinned", screens: model.pinnedScreens)
                }

                DebugScreensListView(model: model, sectionTitle: "Screens", screens: model.unpinnedScreens)
                DebugScreensListView(model: model, sectionTitle: "Actions", screens: model.actions)
            } else {
                DebugScreensListView(model: model, sectionTitle: "Results", screens: model.filtered)
            }
        }
        .searchable(text: $model.filter, prompt: "Filter")
        .navigationTitle("Debug")
        .applyBackground()
    }
}

extension View {
    @ViewBuilder
    func applyBackground() -> some View {
        hideScrollContentBackground()
        .background(
            Rectangle().ignoresSafeArea().foregroundColor(Color(designSystemColor: .background))
        )
    }

    @ViewBuilder
    private func hideScrollContentBackground() -> some View {
        if #available(iOS 16, *) {
            self.scrollContentBackground(.hidden)
        } else {
            let originalBackgroundColor = UITableView.appearance().backgroundColor
            self.onAppear {
                UITableView.appearance().backgroundColor = .clear
            }.onDisappear {
                UITableView.appearance().backgroundColor = originalBackgroundColor
            }
        }
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
