//
//  CrashCollectionOnboardingView.swift
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
import DuckUI
import DesignResourcesKit
import DesignResourcesKitIcons
import MetricBuilder

struct CrashCollectionOnboardingView: View {

    @ObservedObject var model: CrashCollectionOnboardingViewModel

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if #available(iOS 16.0, *) {
                // This is only required because on iPad you get semi-transparent bars either side.
                // Previously it was closed to place the close button but we're placing that explicitly now like
                //  in other sheets.
                NavigationStack {
                    contents
                }
            } else {
                contents
            }
            closeButton
                .padding(16)
        }
        .padding(0)
        .background(Color(designSystemColor: .backgroundTertiary))
    }

    private var closeButton: some View {
        Button {
            model.onDismiss(.undetermined)
        } label: {
            Image(uiImage: DesignSystemImages.Glyphs.Size24.close)
        }
        .buttonStyle(CloseButtonStyle())
        .accessibilityLabel(UserText.keyCommandClose)
    }

    var contents: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: SheetMetrics.contentSpacing) {
                    Image(rebrandable: "Breakage-Alert-128")
                        .accessibilityHidden(true)

                    Text(UserText.crashReportDialogTitle)
                        .daxTitle1()
                        .multilineTextAlignment(.center)
                        .foregroundColor(Color(designSystemColor: .textPrimary))

                    Text(UserText.crashReportDialogMessage)
                        .multilineTextAlignment(.center)
                        .daxBodyRegular()
                        .foregroundColor(Color(designSystemColor: .textPrimary))

                    if let reportDetails = model.reportDetails {
                        VStack(spacing: 4) {

                            reportDetailsButton

                            if model.isReportVisible {
                                ZStack {
                                    Rectangle()
                                        .foregroundColor(Color(designSystemColor: .lines))
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .cornerRadius(4.0)

                                    Text(reportDetails)
                                        .multilineTextAlignment(.leading)
                                        .font(.crashReport)
                                        .foregroundColor(Color(designSystemColor: .textSecondary))
                                        .padding(24)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, SheetMetrics.contentHorizontalPadding)
                .padding(.vertical, 20)
            }
            .modifier(ScrollDisabledIfAvailable(isDisabled: !model.isReportVisible))

            VStack(spacing: 8) {
                Button {
                    withAnimation {
                        model.crashCollectionOptInStatus = .optedIn
                        model.onDismiss(.optedIn)
                    }
                } label: {
                    Text(UserText.crashReportAlwaysSend)
                }
                .buttonStyle(PrimaryButtonStyle())
                .frame(maxWidth: 360)

                Button {
                    withAnimation {
                        model.crashCollectionOptInStatus = .optedOut
                        model.onDismiss(.optedOut)
                    }
                } label: {
                    Text(UserText.crashReportNeverSend)
                }
                .buttonStyle(GhostButtonStyle())
                .frame(maxWidth: 360)
            }
            .padding(.init(top: 24, leading: 24, bottom: 0, trailing: 24))
        }
    }

    var reportDetailsButton: some View {
        Button {
            model.toggleReportVisible()
        } label: {
            HStack {
                if model.showReportButtonMode == .hideDetails {
                    Text(UserText.crashReportHideDetails).daxButton()
                    Image(uiImage: DesignSystemImages.Glyphs.Size24.chevronUpSmall).frame(width: 7, height: 12)
                } else {
                    Text(UserText.crashReportShowDetails).daxButton()
                    Image(uiImage: DesignSystemImages.Glyphs.Size24.chevronDownSmall).frame(width: 7, height: 12)
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundColor(Color(designSystemColor: .textSecondary))
        .frame(height: 44)
    }
}

private extension Font {
    static var crashReport: Font {
        let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .caption2)
        return Font(uiFont: .monospacedSystemFont(ofSize: descriptor.pointSize, weight: .regular))
    }
}

private struct ScrollDisabledIfAvailable: ViewModifier {
    let isDisabled: Bool

    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            return content.scrollDisabled(isDisabled)
        }
        return content
    }
}

#Preview {
    let model = CrashCollectionOnboardingViewModel(appSettings: AppDependencyProvider.shared.appSettings)
    model.setReportDetails(with: ["test report details test report details test report details test report details test report details\n\ntest report details\ntest report details\ntest report details\ntest report details\ntest report details\ntest report details\ntest report details\ntest report details\ntest report details\ntest report details\ntest report details\ntest report details\ntest report details\ntest report details\ntest report details\ntest report details\ntest report details\ntest report details".data(using: .utf8)!])
    return CrashCollectionOnboardingView(model: model)
}
