//
//  SettingsCellDemoDebugView.swift
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

import DesignResourcesKitIcons
import SwiftUI

struct SettingsCellDemoDebugView: View {

    enum SampleOption: String, CaseIterable, Hashable, CustomStringConvertible {
        case optionOne = "Lorem"
        case optionTwo = "Ipsum"
        case optionThree = "Dolor"

        var description: String {
            return self.rawValue
        }
    }

    @State var selectedOption: SampleOption = .optionOne

    func customCellContent() -> some View {
        HStack(spacing: 15) {
            FaviconView(viewModel: .init(domain: "Fake.com", useFakeFavicon: true))
                .frame(width: 64, height: 64)

            Spacer()
            VStack(alignment: .center) {
                Text("CUSTOM CELL CONTENT")
                    .font(.headline)
            }
            Spacer()
            Image(uiImage: DesignSystemImages.Color.Size24.appearance)
                .foregroundColor(.orange)
                .imageScale(.medium)
            Image(uiImage: DesignSystemImages.Color.Size24.appearance)
                .foregroundColor(.orange)
                .imageScale(.large)
        }
    }

    var body: some View {
        Group {
            List {
                SettingsCellView(label: "Cell with disclosure",
                                 disclosureIndicator: true)

                SettingsCellView(label: "Multi-line Cell with disclosure \nLine 2\nLine 3",
                                 subtitle: "Curabitur erat massa, cursus sed velit",
                                 image: Image(uiImage: DesignSystemImages.Color.Size24.identity),
                                 disclosureIndicator: true)

                SettingsCellView(label: "Image cell with disclosure ",
                                 accessory: .image(Image(systemName: "person.circle")),
                                 disclosureIndicator: true)

                SettingsCellView(label: "Subtitle image cell with disclosure",
                                 subtitle: "This is the subtitle",
                                 accessory: .image(Image(uiImage: DesignSystemImages.Color.Size24.privacyPro)),
                                 disclosureIndicator: true)

                SettingsCellView(label: "Greyed out cell",
                                 subtitle: "This is the subtitle",
                                 image: Image(uiImage: DesignSystemImages.Color.Size24.privacyPro),
                                 accessory: .image(Image(uiImage: DesignSystemImages.Color.Size24.exclamation)),
                                 disclosureIndicator: true,
                                 isGreyedOut: true)

                SettingsCellView(label: "Right Detail cell with disclosure",
                                 accessory: .rightDetail("Detail"),
                                 disclosureIndicator: true)

                SettingsCellView(label: "Switch Cell",
                                 image: Image(uiImage: DesignSystemImages.Color.Size24.appearance),
                                 accessory: .toggle(isOn: .constant(true)))

                SettingsCellView(label: "Switch Cell",
                                 subtitle: "Subtitle goes here",
                                 accessory: .toggle(isOn: .constant(true)))

                SettingsPickerCellView(label: "Proin tempor urna", options: SampleOption.allCases, selectedOption: $selectedOption)

                SettingsCustomCell(content: customCellContent)

                SettingsCellView(label: "Cell with image",
                                 image: Image(uiImage: DesignSystemImages.Color.Size24.appearance),
                                 statusIndicator: StatusIndicatorView(status: .off),
                                 disclosureIndicator: true
                )


                SettingsCellView(label: "Cell a long long long long long long long title",
                                 image: Image(uiImage: DesignSystemImages.Color.Size24.appearance),
                                 statusIndicator: StatusIndicatorView(status: .alwaysOn),
                                 disclosureIndicator: true
                )

                SettingsCellView(label: "Cell with everything Lorem ipsum dolor sit amet, consectetur",
                                 subtitle: "Long subtitle Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation",
                                 image: Image(uiImage: DesignSystemImages.Color.Size24.appearance),
                                 accessory: .toggle(isOn: .constant(true)),
                                 statusIndicator: StatusIndicatorView(status: .on),
                                 disclosureIndicator: true
                )
            }
        }
    }
}
