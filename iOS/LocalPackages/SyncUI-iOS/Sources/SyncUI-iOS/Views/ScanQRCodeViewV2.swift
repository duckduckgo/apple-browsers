//
//  ScanQRCodeViewV2.swift
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

import DesignResourcesKit
import DesignResourcesKitIcons
import DuckUI
import SwiftUI
import UIComponents

public struct ScanQRCodeViewV2: View {

    enum Tab {
        case scanQRCode
        case enterCode
    }

    @ObservedObject var model: ScanOrPasteCodeViewModel
    @State private var selectedTab: Tab = .scanQRCode
    @State private var showIntroAnimation = true

    public init(model: ScanOrPasteCodeViewModel) {
        self.model = model
    }

    init(model: ScanOrPasteCodeViewModel, selectedTab: Tab) {
        self.model = model
        _selectedTab = State(initialValue: selectedTab)
    }

    public var body: some View {
        VStack(spacing: 16) {
            segmentedControl
            contentPanel
        }
        .background(SimplifiedSyncStyle.screenBackground)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(UserText.simplifiedScanCloseButton, action: model.cancel)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    model.isShowingSyncCodeSheet = true
                } label: {
                    Image(uiImage: DesignSystemImages.Glyphs.Size24.qr)
                }
            }
        }
        .sheet(isPresented: $model.isShowingSyncCodeSheet, onDismiss: {
            model.onSyncCodeSheetDismissed?()
            model.onSyncCodeSheetDismissed = nil
        }) {
            SyncCodeSheetView(model: model)
        }
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.colorScheme, .dark)
    }

    private var segmentedControl: some View {
        Picker("", selection: $selectedTab) {
            Text(UserText.simplifiedScanTabScanQR)
                .tag(Tab.scanQRCode)
            Text(UserText.simplifiedScanTabEnterCode)
                .tag(Tab.enterCode)
        }
        .pickerStyle(.segmented)
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private var contentPanel: some View {
        switch selectedTab {
        case .scanQRCode:
            ScanTabView(model: model, isCameraActive: !model.isShowingSyncCodeSheet, showIntroAnimation: $showIntroAnimation)
        case .enterCode:
            EnterCodeTabView(model: model)
        }
    }
}

#if DEBUG
#Preview {
    let sampleCode = "https://duckduckgo.com/sync/pairing/#&code2=eyJ2ZXJzaW9uIjoiMiIsImNoYW5uZWxJZCI6IjY4MEQ0NUI1LTVFNkUtNDM0Ny05QzQ0LUI2RkJFODBGQzRBNyIsInB1YmxpY0tleSI6IkFCQ0RFRkdISUpLTE1OT1BRUlNUVVZXWFlaIn0"

    return NavigationView {
        RebrandedPreview(isRebranded: true) {
            ScanQRCodeViewV2(
                model: ScanOrPasteCodeViewModel(codeForDisplayOrPasting: sampleCode, qrCodeString: sampleCode, source: .connect)
            )
        }
    }
}

#Preview("Enter Code") {
    let sampleCode = "https://duckduckgo.com/sync/pairing/#&code2=eyJ2ZXJzaW9uIjoiMiIsImNoYW5uZWxJZCI6IjY4MEQ0NUI1LTVFNkUtNDM0Ny05QzQ0LUI2RkJFODBGQzRBNyIsInB1YmxpY0tleSI6IkFCQ0RFRkdISUpLTE1OT1BRUlNUVVZXWFlaIn0"

    return NavigationView {
        RebrandedPreview(isRebranded: true) {
            ScanQRCodeViewV2(
                model: ScanOrPasteCodeViewModel(codeForDisplayOrPasting: sampleCode, qrCodeString: sampleCode, source: .connect),
                selectedTab: .enterCode
            )
        }
    }
}
#endif
