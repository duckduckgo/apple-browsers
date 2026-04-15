//
//  SimplifiedScanOrShowCodeView.swift
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

public struct SimplifiedScanOrShowCodeView: View {

    enum Tab {
        case scanQRCode
        case viewCode
    }

    @ObservedObject var model: ScanOrPasteCodeViewModel
    @State var qrCodeModel: ShowQRCodeViewModel
    @State private var selectedTab: Tab = .scanQRCode

    public init(model: ScanOrPasteCodeViewModel) {
        self.model = model
        self.qrCodeModel = model.showQRCodeModel
    }

    public var body: some View {
        VStack(spacing: 16) {
            segmentedControl
                .padding(.top, 8)

            contentPanel
        }
        .background(SimplifiedSyncStyle.screenBackground)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(UserText.cancelButton, action: model.cancel)
                    .foregroundColor(.white)
            }
            ToolbarItem(placement: .principal) {
                Text(UserText.simplifiedScanTitle)
                    .daxHeadline()
                    .foregroundColor(.white)
            }
        }
        .navigationBarBackButtonHidden(true)
    }

    // MARK: - Segmented Control

    private var segmentedControl: some View {
        Picker("", selection: $selectedTab) {
            Text(UserText.simplifiedScanTabScanQRCode).tag(Tab.scanQRCode)
                .padding(.horizontal, 4)
            Text(UserText.simplifiedScanTabViewCode).tag(Tab.viewCode)
                .padding(.horizontal, 4)
        }
        .pickerStyle(.segmented)
        .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: - Content Panel

    private var contentPanel: some View {
        ZStack {
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(baseColor: .gray85))
            }
            .ignoresSafeArea(edges: .bottom)

            Group {
                switch selectedTab {
                case .scanQRCode:
                    scanTabContent
                case .viewCode:
                    viewCodeTabContent
                }
            }
        }
    }
}

enum SimplifiedSyncStyle {
    static let screenBackground = Color(baseColor: .gray90)
    static let instructionText = Color(baseColor: .gray30)
    static let primaryActionBackground = Color(baseColor: .blue20)
    static let subduedPanelBackground = Color.white.opacity(0.09)

    // Using this instead of a design system color, because the associated design system color
    // is semi-opaque and doesn't give us the correct appearance when we layer up the
    // various elements of the QR code panel.
    static let qrCodeBackground = Color(red: 0.92, green: 0.92, blue: 0.92)
}
