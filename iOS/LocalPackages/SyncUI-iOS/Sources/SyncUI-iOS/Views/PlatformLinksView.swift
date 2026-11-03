//
//  PlatformLinksView.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import DesignResourcesKit
import DesignResourcesKitIcons
import DuckUI
import MetricBuilder

#if DEBUG
import PreviewSnapshots
#endif

public struct PlatformLinksView: View {

    private struct Constants {
        static let goToUrl: String = "duckduckgo.com/app"
        static let downloadUrl: String = "https://duckduckgo.com/app?origin=funnel_browser_ios_sync"
    }

    private var model: SyncSettingsViewModel
    private var source: SyncSettingsViewModel.PlatformLinksPixelSource

    @State private var shareButtonFrame: CGRect = .zero

    public init(model: SyncSettingsViewModel, source: SyncSettingsViewModel.PlatformLinksPixelSource) {
        self.model = model
        self.source = source
    }

    public var body: some View {
        ScrollView {
            VStack {
                content
                Spacer()
            }
            .padding(16)
            .frame(maxWidth: .infinity)
        }
        .background(Color(designSystemColor: .background).ignoresSafeArea())
        .navigationTitle(UserText.syncGetOtherDevicesScreenTitle)
    }

    private var content: some View {
        VStack(alignment: .center, spacing: 8) {
            Image("DDG-App-Download-Feature-96", bundle: .module)
                .resizable()
                .frame(width: 96, height: 96)

            VStack(spacing: 8) {
                Text(UserText.syncGetOtherDevicesTitle)
                    .daxHeadline()
                    .foregroundColor(Color(designSystemColor: .textPrimary))

                VStack(spacing: 0) {
                    Text(UserText.syncGetOtherDevicesMessage)
                        .daxSubheadRegular()
                        .foregroundColor(Color(designSystemColor: .textSecondary))

                    Text(Constants.goToUrl)
                        .font(Font(UIFont.daxSubheadRegular()).weight(.medium))
                        .foregroundColor(Color(designSystemColor: .accentPrimary))
                        .overlay(
                            CopyActionOverlay(copyText: Constants.downloadUrl, onCopy: {
                                model.fireOtherPlatformLinksPixel(for: .copy, source: source)
                            })
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        )
                }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .padding(.vertical, 8)

            Button {
                if let url = URL(string: Constants.downloadUrl) {
                    model.shareLinkPressed(for: url, with: UserText.syncGetOtherDeviceShareLinkMessage, from: shareButtonFrame)
                    model.fireOtherPlatformLinksPixel(for: .share, source: source)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(uiImage: DesignSystemImages.Glyphs.Size24.shareApple)
                    Text(UserText.syncGetOtherDevicesButtonTitle)
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .background(
                GeometryReader { geometryProxy in
                    Color.clear
                        .preference(key: ShareButtonFramePreferenceKey.self, value: geometryProxy.frame(in: .global))
                }
            )
            .onPreferenceChange(ShareButtonFramePreferenceKey.self) { newFrameRect in
                shareButtonFrame = newFrameRect
            }
            .padding(8)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: ContainerMetrics.cornerRadius)
                .fill(Color(designSystemColor: .surfaceSecondary))
        )
        .onAppear {
            model.fireOtherPlatformLinksPixel(for: .appear, source: source)
        }
    }
}

private struct ShareButtonFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct CopyActionOverlay: UIViewRepresentable {
    let copyText: String
    let onCopy: () -> Void

    class Coordinator: NSObject {
        var copyText: String
        var onCopy: () -> Void

        init(copyText: String, onCopy: @escaping () -> Void) {
            self.copyText = copyText
            self.onCopy = onCopy
        }

        @objc func showMenu(_ sender: UITapGestureRecognizer) {
            guard let view = sender.view else { return }
            view.becomeFirstResponder()

            let menuController = UIMenuController.shared
            menuController.menuItems = [
                UIMenuItem(title: UserText.copyButton, action: #selector(copyTextAction))
            ]
            menuController.showMenu(from: view, rect: view.bounds)
        }

        @objc func copyTextAction() {
            UIPasteboard.general.string = copyText

            onCopy()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(copyText: copyText, onCopy: onCopy)
    }

    func makeUIView(context: Context) -> UIView {
        let view = CopyableUIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = true

        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.showMenu(_:)))
        view.addGestureRecognizer(tapGesture)

        view.copyAction = context.coordinator.copyTextAction
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

private class CopyableUIView: UIView {
    var copyAction: (() -> Void)?

    override var canBecomeFirstResponder: Bool {
        return true
    }

    override func copy(_ sender: Any?) {
        copyAction?()
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(copy(_:)) {
            return true
        }
        return super.canPerformAction(action, withSender: sender)
    }
}

#if DEBUG
struct PlatformLinksView_Previews: PreviewProvider {

    static var previews: some View {
        snapshots.previews
    }

    static let snapshots = PreviewSnapshots<Void>(
        configurations: [
            .init(name: "Platform Links", state: ())
        ],
        configure: { _ in
            PreviewNavigationContainer {
                PlatformLinksView(
                    model: SyncSettingsViewModel(
                        isOnDevEnvironment: { true },
                        switchToProdEnvironment: {},
                        autoRestoreProvider: SyncAutoRestorePreviewProvider.disabled
                    ),
                    source: .activated
                )
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    )
}
#endif
