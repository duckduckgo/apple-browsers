//
//  HapticsPlaygroundView.swift
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

import SwiftUI
import Bookmarks
import WebExtensions
import Onboarding
import CoreHaptics

struct HapticsPlaygroundView: View {
    @StateObject private var viewModel = HapticsPlaygroundViewModel()

    @State private var isTimingSectionExpanded = false
    @State private var isIntensitySectionExpanded = false
    @State private var isSharpnessExpanded = false

    var body: some View {
        let duration = viewModel.animationDuration

        List {
            animationSection
            baseSection
            timingSection(animationDuration: duration)
            intensitySection(animationDuration: duration)
            sharpnessSection(animationDuration: duration)
            resetSection
            previewSection

        }
        .background(Color(designSystemColor: .background))
    }

    private var animationSection: some View {
        Section {
            SettingsPickerCellView(
                label: UserText.settingsFirebutton,
                options: viewModel.animations,
                selectedOption: viewModel.fireButtonAnimationBinding
            )
        } header: {
            Text(verbatim: "Animation:")
        }
    }

    private var baseSection: some View {
        Section {

            FloatSlider(
                title: "Strength",
                value: $viewModel.configuration.baseIntensity,
                range: 0...1
            )

            FloatSlider(
                title: "Texture",
                value: $viewModel.configuration.baseSharpness,
                range: 0...1
            )
        } header: {
            Text(verbatim: "Base Values")
        } footer: {
            Text(
                """
                Strength controls how strong the haptic feels.

                Texture controls its character: lower values feel softer and rounder, while higher values feel crisper and more precise.
                """
            )
        }
    }

    private func timingSection(animationDuration: TimeInterval) -> some View {
        Section {
            DisclosureGroup(
                "Timing (advanced)",
                isExpanded: $isTimingSectionExpanded
            ) {
                ProgressSlider(
                    title: "Start",
                    value: $viewModel.configuration.hapticStart
                )

                ProgressSlider(
                    title: "End",
                    value: $viewModel.configuration.hapticEnd
                )

                Text("Animation Duration: \(animationDuration, format: .number.precision(.fractionLength(2))) s")


                Text("Haptic start: \(viewModel.configuration.hapticStart * animationDuration, format: .number.precision(.fractionLength(3))) s")


                Text("Haptic end \(viewModel.configuration.hapticEnd * animationDuration, format: .number.precision(.fractionLength(3))) s")
            }
        } header: {
            Text(verbatim: "Timing")
        } footer: {
            Text(
                "Start and End define where the continuous haptic begins and finishes relative to the animation."
            )
        }
    }

    private func intensitySection(animationDuration: TimeInterval) -> some View {
        Section {
            DisclosureGroup(
                "Strength (advanced)",
                isExpanded: $isIntensitySectionExpanded
            ) {
                ForEach($viewModel.configuration.intensityPoints) { $point in
                    HapticCurvePointEditor(
                        title: "\(Int(point.progress * 100))% Point",
                        animationDuration: animationDuration,
                        valueTitle: "Strength",
                        point: $point
                    )
                }
            }
        } header: {
            Text("Strength (Advanced)")
        } footer: {
            Text(
                "Each point describes how strong the haptic should feel at a particular moment. iOS smoothly transitions between the points."
            )
        }
    }

    private func sharpnessSection(animationDuration: TimeInterval) -> some View {
        Section {
            DisclosureGroup(
                "Texture (advanced)",
                isExpanded: $isSharpnessExpanded
            ) {
                ForEach($viewModel.configuration.sharpnessPoints) { $point in
                    HapticCurvePointEditor(
                        title: "\(Int(point.progress * 100))% Point",
                        animationDuration: animationDuration,
                        valueTitle: "Strength",
                        point: $point
                    )
                }
            }
        } header: {
            Text(verbatim: "Texture Curve")
        } footer: {
            Text(
                "Texture changes the texture of the haptic over time. Lower values feel softer and more rounded; higher values feel sharper and more click-like."
            )
        }
    }

    private var resetSection: some View {
        Section {
            Button("Reset to Default", role: .destructive) {
                viewModel.resetValues()
            }
        } footer: {
            Text("Restores all haptic settings to their original values.")
        }
    }

    private var previewSection: some View {
        Section {
            Button(action: viewModel.testHaptic) {
                Text(verbatim: "Play Fire Animation + Haptics!!!")
            }
        } header: {
            Text(verbatim: "Test Selected Haptic")
        }
    }
}

struct ProgressSlider: View {
    let title: String
    @Binding var value: Double

    var body: some View {
        VStack(alignment: .leading) {

            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value * 100))%")
                    .monospacedDigit()
            }

            Slider(
                value: $value,
                in: 0...1
            )
        }
    }

}

struct FloatSlider: View {
    let title: String
    @Binding var value: Float
    let range: ClosedRange<Double>

    var body: some View {
        VStack(alignment: .leading) {

            HStack {
                Text(title)

                Spacer()

                Text(
                    String(
                        format: "%.2f",
                        value
                    )
                )
                .monospacedDigit()
            }

            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { value = Float($0) }
                ),
                in: range
            )
        }
    }
}

struct HapticCurvePointEditor: View {
    let title: String
    let animationDuration: TimeInterval
    let valueTitle: String

    @Binding var point: HapticPoint

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            Text(title)
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Time")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(
                        "\(Int(point.progress * 100))% · \(point.progress * animationDuration, specifier: "%.3f")s"
                    )
                    .font(.caption.monospacedDigit())
                }

                Slider(
                    value: $point.progress,
                    in: 0...1
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(valueTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(point.value, specifier: "%.2f")")
                        .font(.caption.monospacedDigit())
                }

                Slider(
                    value: Binding(
                        get: { Double(point.value) },
                        set: { point.value = Float($0) }
                    ),
                    in: 0...1
                )
            }
        }
        .padding(.vertical, 8)
    }
}

final class HapticsPlaygroundViewModel: ObservableObject {
    @Published private var fireButtonAnimation: FireButtonAnimationType {
        didSet {
            configuration = fireButtonAnimation.hapticConfiguration
        }
    }

    @Published var configuration: HapticConfiguration

    let animations = [FireButtonAnimationType.fireRising, .fireRisingLegacy, .waterSwirl, .airstream]

    private let appSettings: AppSettings
    private let animator: FireButtonAnimator
    private let hapticEngine: HapticEngine

    var animationDuration: TimeInterval {
        fireButtonAnimation.duration
    }

    init(appSettings: AppSettings = InMemoryAppSettings()) {
        self.appSettings = appSettings
        configuration = animations.first!.hapticConfiguration
        animator = FireButtonAnimator(appSettings: appSettings)
        fireButtonAnimation = appSettings.currentFireButtonAnimation
        hapticEngine = HapticEngine()
    }

    var fireButtonAnimationBinding: Binding<FireButtonAnimationType> {
        Binding<FireButtonAnimationType>(
            get: {
                self.fireButtonAnimation
            },
            set: {
                self.fireButtonAnimation = $0
                self.appSettings.currentFireButtonAnimation = $0
                NotificationCenter.default.post(name: AppUserDefaults.Notifications.currentFireButtonAnimationChange, object: self)
            }
        )
    }

    func resetValues() {
        configuration = fireButtonAnimation.hapticConfiguration
    }

    func testHaptic() {
        self.animator.animate {
            // no op
        } onTransitionCompleted: {
            // no op
        } completion: {
            // no op
        }
        self.hapticEngine.play(haptic: configuration, duration: fireButtonAnimationBinding.wrappedValue.duration)
    }
}

// MARK: - Haptics

struct HapticPoint: Identifiable, Equatable {
    let id = UUID()
    var progress: Double       // 0...1 relative to animation
    var value: Float
}

struct HapticConfiguration {
    var baseIntensity: Float
    var baseSharpness: Float

    var hapticStart: Double
    var hapticEnd: Double

    var intensityPoints: [HapticPoint]
    var sharpnessPoints: [HapticPoint]

    var transientEnabled = true
    var transientProgress: Double
    var transientIntensity: Float
    var transientSharpness: Float
}

extension HapticConfiguration {

    static let inferno = HapticConfiguration(
        baseIntensity: 1.0,
        baseSharpness: 0.20,
        hapticStart: 0.17,
        hapticEnd: 0.82,
        intensityPoints: [
            .init(progress: 0.17, value: 0.0),
            .init(progress: 0.28, value: 0.15),
            .init(progress: 0.40, value: 0.45),
            .init(progress: 0.52, value: 1.0),
            .init(progress: 0.60, value: 0.70),
            .init(progress: 0.72, value: 0.25),
            .init(progress: 0.82, value: 0.0)
        ],
        sharpnessPoints: [
            .init(progress: 0.17, value: 0.0),
            .init(progress: 0.35, value: 0.10),
            .init(progress: 0.52, value: 0.35),
            .init(progress: 0.62, value: 0.15),
            .init(progress: 0.82, value: 0.0)
        ],
        transientEnabled: true,
        transientProgress: 0.52,
        transientIntensity: 0.35,
        transientSharpness: 0.65
    )

}

private extension FireButtonAnimationType {

    var duration: TimeInterval {
        switch self {
        case .fireRising:
            return 1.17
        case.fireRisingLegacy, .airstream, .waterSwirl:
            return 1.0
        case .none:
            return 0
        }
    }

    var hapticConfiguration: HapticConfiguration {
        .inferno
    }

}

final class HapticEngine {
    private var engine: CHHapticEngine?
    private var player: CHHapticAdvancedPatternPlayer?

    init() {
       prepare()
    }

    func play(haptic: HapticConfiguration, duration: TimeInterval) {
        play(haptic: haptic, animationDuration: duration)
    }
}

private extension HapticEngine {

    func prepare() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            return
        }

        do {
            engine = try CHHapticEngine()
            try engine?.start()
        } catch {
            print("Haptics engine error:", error)
        }
    }

    func play(
        haptic: HapticConfiguration,
        animationDuration: TimeInterval
    ) {
        guard let engine else { return }

        do {
            let pattern = try makePattern(
                haptic: haptic,
                animationDuration: animationDuration
            )

            player = try engine.makeAdvancedPlayer(with: pattern)
            try player?.start(atTime: CHHapticTimeImmediate)

        } catch {
            print("Haptic playback error:", error)
        }
    }

    func makePattern(
        haptic: HapticConfiguration,
        animationDuration: TimeInterval
    ) throws -> CHHapticPattern {

        let startTime =
        haptic.hapticStart * animationDuration

        let endTime =
        haptic.hapticEnd * animationDuration

        let duration =
        endTime - startTime

        let continuous = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                .init(
                    parameterID: .hapticIntensity,
                    value: haptic.baseIntensity
                ),
                .init(
                    parameterID: .hapticSharpness,
                    value: haptic.baseSharpness
                )
            ],
            relativeTime: startTime,
            duration: duration
        )

        let intensityCurve = CHHapticParameterCurve(
            parameterID: .hapticIntensityControl,
            controlPoints: haptic.intensityPoints.map { point in

                CHHapticParameterCurve.ControlPoint(
                    relativeTime:
                        point.progress * animationDuration - startTime,
                    value: point.value
                )
            },
            relativeTime: startTime
        )

        let sharpnessCurve = CHHapticParameterCurve(
            parameterID: .hapticSharpnessControl,
            controlPoints: haptic.sharpnessPoints.map { point in

                CHHapticParameterCurve.ControlPoint(
                    relativeTime:
                        point.progress * animationDuration - startTime,
                    value: point.value
                )
            },
            relativeTime: startTime
        )

        var events: [CHHapticEvent] = [continuous]

        if haptic.transientEnabled {

            let transient = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    .init(
                        parameterID: .hapticIntensity,
                        value: haptic.transientIntensity
                    ),
                    .init(
                        parameterID: .hapticSharpness,
                        value: haptic.transientSharpness
                    )
                ],
                relativeTime:
                    haptic.transientProgress * animationDuration
            )

            events.append(transient)
        }

        return try CHHapticPattern(
            events: events,
            parameterCurves: [
                intensityCurve,
                sharpnessCurve
            ]
        )
    }

}


final class InMemoryAppSettings: AppSettings {
    var currentFireButtonAnimation: FireButtonAnimationType = .fireRising

    var autocomplete: Bool = false

    var recentlyVisitedSites: Bool = false

    var currentThemeStyle: ThemeStyle = .systemDefault

    var autoClearAction: FireRequest.Options = .all

    var autoClearTiming: AutoClearSettingsModel.Timing = .delay15min

    var longPressPreviews: Bool = false

    var allowUniversalLinks: Bool = false

    var sendDoNotSell: Bool = false

    var currentAddressBarPosition: AddressBarPosition = .top

    var keepAddressBarVisibleOnIPad: Bool = false

    var currentRefreshButtonPosition: RefreshButtonPosition = .addressBar

    var showFullSiteAddress: Bool = false

    var showTrackersBlockedAnimation: Bool = false

    var defaultTextZoomLevel: TextZoomLevel = .percent100

    var favoritesDisplayMode: Bookmarks.FavoritesDisplayMode = .default

    var autofillCredentialsEnabled: Bool = false

    var autofillCreditCardsEnabled: Bool = false

    var autofillCredentialsSavePromptShowAtLeastOnce: Bool = false

    var autofillCredentialsHasBeenEnabledAutomaticallyIfNecessary: Bool = false

    var autofillIsNewInstallForOnByDefault: Bool?
    
    func setAutofillIsNewInstallForOnByDefault() {}
    
    var autofillImportViaSyncStart: Date?
    
    func clearAutofillImportViaSyncStart() {}
    
    var voiceSearchEnabled: Bool = false

    func isWidgetInstalled() async -> Bool { false }

    var autoconsentEnabled: Bool = false

    var cookiePopupPreference: WebExtensions.CookiePopupPreference = .default

    var crashCollectionOptInStatus: CrashCollectionOptInStatus = .optedIn

    var crashCollectionShouldRevertOptedInStatusTrigger: Int = 0

    var duckPlayerMode: DuckPlayerMode = .alwaysAsk

    var duckPlayerAskModeOverlayHidden: Bool = false

    var duckPlayerOpenInNewTab: Bool = false

    var duckPlayerAutoplay: Bool = false

    var duckPlayerNativeUISERPEnabled: Bool = false

    var duckPlayerNativeYoutubeMode: NativeDuckPlayerYoutubeMode = .ask

    var duckPlayerPillDismissCount: Int = 0

    var duckPlayerPrimingMessagePresented: Bool = false

    var duckPlayerVariant: DuckPlayerVariant = .classicWeb

    var duckPlayerWelcomeMessageShown: Bool = false

    var duckPlayerControlsVisible: Bool = false

    var duckPlayerNativeUIWasUsed: Bool = false

    var duckPlayerNativeUISettingsMapped: Bool = false

    var autoClearAIChatHistory: Bool = false

    var onboardingUserType: OnboardingUserType = .newUser

    var onboardingForceRestorePromptEligible: Bool = false

    var onboardingFlowType: OnboardingFlowType?
}
