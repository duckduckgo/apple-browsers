//
//  DebugViewController.swift
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

class DebugViewController: UIHostingController<RootDebugView> {

    convenience init(pushController: @escaping (UIViewController) -> Void) {
        self.init(rootView: RootDebugView(model: RootDebugModel(pushController: pushController)))
    }

}

struct RootDebugView: View {

    @ObservedObject var model: RootDebugModel

    var body: some View {
        List {
            Toggle(isOn: $model.isInternalUser) {
                Label {
                    Text(verbatim: "Internal User")
                } icon: {
                    Image(systemName: "flask")
                }
            }

            Section {
                ForEach(model.visibleDebugViews) {
                    switch $0 {
                    case .controller(let title, let controller):
                        SettingsCellView(label: title, action: {
                            model.pushController(controller())
                        }, disclosureIndicator: true, isButton: true)

                    case .view(let title, _):
                        NavigationLink(title, destination: $0.view)
                    }
                }
            }

        }
        .searchable(text: $model.filter, prompt: "Filter")
        .navigationTitle("Debug")
    }

}

class RootDebugModel: ObservableObject {

    let allDebugViews: [DebugViewBuilder] = [
        .view(title: "SwiftUI View", {
            Image(.addToHome16)
        }),
        .view(title: "Beta Test", {
            Image(.adobe)
        }),
        .controller(title: "AI Chat", {
            UIHostingController(rootView: AIChatDebugView())
        }),
    ]

    @Published var isInternalUser = false
    @Published var filter = "" {
        didSet {
            refreshFilter()
        }
    }
    @Published var visibleDebugViews: [DebugViewBuilder] = []

    let pushController: (UIViewController) -> Void

    init(pushController: @escaping (UIViewController) -> Void) {
        self.pushController = pushController
        refreshFilter()
    }

    func refreshFilter() {
        if filter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.visibleDebugViews = allDebugViews
        } else {
            self.visibleDebugViews = allDebugViews.filter {
                $0.title.lowercased().contains(filter.lowercased())
            }
        }
        self.visibleDebugViews = self.visibleDebugViews.sorted(by: {
            $0.title < $1.title
        })
    }

}

enum DebugViewBuilder: Identifiable {

    case controller(title: String, () -> UIViewController)
    case view(title: String, () -> any View)

    var id: String {
        return title
    }

    var title: String {
        switch self {
        case .controller(let title, _):
            return title

        case .view(let title, _):
            return title
        }
    }

    var view: AnyView {
        switch self {
        case .view(_, let builder):
            return AnyView(builder())
        default:
            return AnyView(Text(verbatim: "Unexpected"))
        }
    }

}
