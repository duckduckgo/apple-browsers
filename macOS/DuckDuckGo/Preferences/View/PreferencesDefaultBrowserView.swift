//
//  PreferencesDefaultBrowserView.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

import AppKit
import PreferencesUI_macOS
import SwiftUI
import SwiftUIExtensions
import PixelKit
import DesignResourcesKitIcons

extension Preferences {

    struct DefaultBrowserView: View {
        @ObservedObject var defaultBrowserModel: DefaultBrowserPreferences
        @ObservedObject var dockModel: DockPreferencesModel
        let protectionStatus: PrivacyProtectionStatus?

        private var isPresentingAddToDockDemoVideo: Binding<Bool> {
            Binding(
                get: { dockModel.isPresentingAddToDockDemoVideo },
                set: { dockModel.isPresentingAddToDockDemoVideo = $0 }
            )
        }

        var body: some View {
            PreferencePane(UserText.defaultBrowser, spacing: 4) {

                // SECTION 1: Status Indicator
                if let status = protectionStatus?.status {
                    PreferencePaneSection {
                        StatusIndicatorView(status: status, isLarge: true)
                    }
                }

                // SECTION 2: Default Browser
                PreferencePaneSection {

                    PreferencePaneSubSection {
                        HStack {
                            if defaultBrowserModel.isDefault {
                                Text(UserText.isDefaultBrowser)
                            } else {
                                HStack {
                                    Image(.warning).foregroundColor(Color(.linkBlue))
                                    Text(UserText.isNotDefaultBrowser)
                                }
                                .padding(.trailing, 8)
                                Button(action: {
                                    PixelKit.fire(GeneralPixel.defaultRequestedFromSettings)
                                    defaultBrowserModel.becomeDefault()
                                }) {
                                    Text(UserText.makeDefaultBrowser)
                                        .fixedSize(horizontal: true, vertical: false)
                                        .multilineTextAlignment(.center)
                                }
                            }
                        }
                    }

                    Spacer().frame(height: 16)

                    if dockModel.canAddToDock {
                        PreferencePaneSection(UserText.shortcuts, spacing: 4) {
                            PreferencePaneSubSection {
                                HStack {
                                    if dockModel.isAddedToDock {
                                        HStack {
                                            Image(.checkCircle).foregroundColor(Color(.successGreen))
                                            Text(UserText.isAddedToDock)
                                        }
                                        .transition(.opacity)
                                        .padding(.trailing, 8)
                                    } else {
                                        HStack {
                                            Image(.warning).foregroundColor(Color(.linkBlue))
                                            Text(UserText.isNotAddedToDock)
                                        }
                                        .padding(.trailing, 8)
                                        Button(action: {
                                            withAnimation {
                                                dockModel.addToDock(from: .defaultBrowser)
                                            }
                                        }) {
                                            Text(UserText.addToDock)
                                                .fixedSize(horizontal: true, vertical: false)
                                                .multilineTextAlignment(.center)
                                        }
                                    }
                                }
                            }
                        }
                        .onAppear {
                            dockModel.refresh()
                        }
                    } else if dockModel.canShowDockInstructions {
                        PreferencePaneSection(UserText.shortcuts, spacing: 4) {
                            PreferencePaneSubSection {
                                HStack(alignment: .top) {
                                    Image(nsImage: DesignSystemImages.Glyphs.Size16.addToTaskbar)
                                        .foregroundColor(Color(.linkBlue))
                                    Text(UserText.addToDockInstructions)
                                }
                                VStack(alignment: .leading, spacing: 1) {
                                    TextMenuItemCaption(UserText.addToDockInstructionsCaption)
                                    TextButton(UserText.addToDockShowMeHow) {
                                        dockModel.showAddToDockDemoVideo()
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: isPresentingAddToDockDemoVideo) {
                PreferencesVideoSheet(videoURL: DockPreferencesModel.demoVideoURL,
                                      videoSize: DockPreferencesModel.demoVideoSize,
                                      isPresented: isPresentingAddToDockDemoVideo)
            }
        }
    }
}
