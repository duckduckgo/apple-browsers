//
//  VPNUpsellPopover.swift
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

import AppKit
import BrowserServicesKit
import Carbon.HIToolbox
import DesignResourcesKit
import Lottie
import Subscription
import SwiftUI
import SwiftUIExtensions

// MARK: - ViewModel

extension VPNUpsellPopoverViewModel {
    struct FeatureStatus {
        let isEligibleForFreeTrial: Bool
        let isPIRFeatureEnabled: Bool
        let hasAIChatFeature: Bool
        
        static var `default`: Self {
            Self(isEligibleForFreeTrial: false, isPIRFeatureEnabled: false, hasAIChatFeature: false)
        }
        
        var plusFeatureCount: Int {
            var count = 1
            if hasAIChatFeature { count += 1 }
            if isPIRFeatureEnabled { count += 1 }
            return count
        }
    }
}

final class VPNUpsellPopoverViewModel {
    let primaryButtonAction: () -> Void
    let secondaryButtonAction: () -> Void
    
    @Published private(set) var featureEligibility: FeatureStatus = .default
    
    private let subscriptionManager: any SubscriptionAuthV1toV2Bridge
    private let featureFlagger: FeatureFlagger
    
    init(subscriptionManager: any SubscriptionAuthV1toV2Bridge,
         featureFlagger: FeatureFlagger,
         primaryButtonAction: @escaping () -> Void,
         secondaryButtonAction: @escaping () -> Void)
    {
        self.subscriptionManager = subscriptionManager
        self.featureFlagger = featureFlagger
        
        self.primaryButtonAction = primaryButtonAction
        self.secondaryButtonAction = secondaryButtonAction
        
        checkFeatureEligibility()
    }
    
    private func checkFeatureEligibility() {
        Task { @MainActor in
            let isPIRFeatureEnabled = try? await subscriptionManager.isFeatureIncludedInSubscription(.dataBrokerProtection)
            let isEligibleForFreeTrial = subscriptionManager.isUserEligibleForFreeTrial()
            let hasAIChatFeature = featureFlagger.isFeatureOn(.paidAIChat)
            
            self.featureEligibility = FeatureStatus(
                isEligibleForFreeTrial: isEligibleForFreeTrial,
                isPIRFeatureEnabled: isPIRFeatureEnabled ?? false,
                hasAIChatFeature: hasAIChatFeature
            )
        }
    }
}

// MARK: - SwiftUI View

struct VPNUpsellPopoverView: View {
    private let viewModel: VPNUpsellPopoverViewModel
    
    init(viewModel: VPNUpsellPopoverViewModel) {
        self.viewModel = viewModel
    }
    
    var body: some View {
        VStack(spacing: 16) {
            LottieView(animation: .named("privacypro_devices"))
                .playing(loopMode: .playOnce)
                .frame(width: 256, height: 96)
                .clipped()
                .padding(.horizontal, 48)
            
            VStack(spacing: 28) {
                titleAndSubtitle
                    .padding(.horizontal, 36)
                features
                    .padding(.horizontal, 48)
            }
            
            actionButtons
                .padding(.top, 12)
        }
        .padding(.top, 28)
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
    }
    
    var titleAndSubtitle: some View {
        VStack(spacing: 8) {
            Text("A VPN to secure your\nWi-Fi & personal info")
                .font(.title3.weight(.semibold))
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .multilineTextAlignment(.center)
                .lineLimit(nil)
            
            Text(plusFeaturesSubtitle)
                .font(.subheadline)
                .foregroundColor(Color(designSystemColor: .textSecondary))
                .multilineTextAlignment(.center)
        }
    }
    
    var features: some View {
        VStack(spacing: 12) {
            coreFeatures
            plusFeatures
        }
    }
    
    var coreFeatures: some View {
        VStack(spacing: 12) {
            FeatureRow(text: "Hide your IP address from sites")
            FeatureRow(text: "Shield your online activity from others")
            FeatureRow(text: "Block harmful sites & online scams")
        }
    }
    
    var plusFeatures: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                horizontalLine
                Text("PLUS")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color(designSystemColor: .textSecondary))
                horizontalLine
            }
            .padding(.vertical, 4)
            
            if viewModel.featureEligibility.hasAIChatFeature {
                FeatureRow(text: "Chat privately with advanced AI models")
            }
            
            FeatureRow(text: "Restore your identity if it's stolen")
            
            if viewModel.featureEligibility.isPIRFeatureEnabled {
                FeatureRow(text: "Remove info from sites that sell it",
                           subtitle: "(currently available on Mac & Windows)")
            }
        }
    }
    
    var actionButtons: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.secondaryButtonAction()
            } label: {
                Text("No Thanks")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(StandardButtonStyle())
            
            Button {
                viewModel.primaryButtonAction()
            } label: {
                Text(viewModel.featureEligibility.isEligibleForFreeTrial ? "Try For Free" : "Learn More")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(DefaultActionButtonStyle(enabled: true, shouldBeFixedVertical: false))
        }
        .frame(height: 28)
    }
    
    var horizontalLine: some View {
        Rectangle()
            .foregroundColor(.clear)
            .frame(maxWidth: .infinity, minHeight: 1, maxHeight: 1)
            .background(Color(designSystemColor: .controlsFillPrimary))
            .cornerRadius(2)
    }
    
    private var plusFeaturesSubtitle: String {
        let plusCount = viewModel.featureEligibility.plusFeatureCount
        return plusCount > 1 ? "+ \(plusCount) more premium protections" : "+ more premium protections"
    }
}

// MARK: - Feature Row

private struct FeatureRow: View {
    let text: String
    let subtitle: String?
    
    init(text: String, subtitle: String? = nil) {
        self.text = text
        self.subtitle = subtitle
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(designSystemColor: .accent))
                .frame(width: 16, height: 16)
                .padding(.top, 2)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(text)
                    .font(.body)
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                    .fixedSize(horizontal: false, vertical: true)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(Color(designSystemColor: .textSecondary))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - NSPopover

final class VPNUpsellPopover: NSPopover {
    private static let topInset: CGFloat = 22
    
    init(viewController: NSHostingController<some View>) {
        super.init()
        
        behavior = .semitransient
        contentViewController = viewController
    }
    
    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("VPNUpsellPopover: Bad initializer")
    }
    
    override func keyDown(with event: NSEvent) {
        if Int(event.keyCode) == kVK_Escape {
            performClose(nil)
        } else {
            super.keyDown(with: event)
        }
    }
}
