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

    var model: DebugScreensViewModel?

    convenience init(dependencies: DebugScreen.Dependencies,
                     pushController: @escaping (UIViewController) -> Void) {

        let model = DebugScreensViewModel(dependencies: dependencies,
                                   pushController: pushController)

        self.init(rootView: DebugScreensView(model: model))

        self.model = model
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // We only need this because the legacy controller can change the state.
        //  Once the legacy controller is gone this can be removed.
        model?.refreshToggles()
    }

}

struct DebugScreensView: View {

    @ObservedObject var model: DebugScreensViewModel

    var body: some View {
        List {
            DebugTogglesView(model: model)

            Section {
                ForEach(model.visibleScreens) { screen in
                    switch screen {
                    case .controller(let title, _):
                        SettingsCellView(label: title, action: {
                            model.navigateToController(screen)
                        }, disclosureIndicator: true, isButton: true)

                    case .view(let title, _):
                        NavigationLink(destination: LazyView(model.buildView(screen))) {
                            SettingsCellView(
                                label: title
                            )
                        }
                    }
                }
            }

            Section {
                SettingsCellView(label: "Legacy Debug", action: {
                    model.navigateToLegacyDebugController()
                }, disclosureIndicator: true, isButton: true)
            }
        }
        .searchable(text: $model.filter, prompt: "Filter")
        .navigationTitle("Debug")
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
