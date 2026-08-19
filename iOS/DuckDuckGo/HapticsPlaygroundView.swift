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
            previewSection
            exportSection
            resetSection

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

    var exportSection: some View {
        Section {
            Button {
                viewModel.exportConfiguration()
            } label: {
                Label(
                    viewModel.didCopyPreset ? "Copied" : "Copy Swift Preset",
                    systemImage: viewModel.didCopyPreset ? "checkmark" : "doc.on.doc"
                )
            }
        } header: {
            Text(verbatim: "Export")
        } footer: {
            Text(verbatim: "Copies the current values as a Swift HapticDesign preset.")
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
            didCopyPreset = false
        }
    }

    @Published var configuration: HapticConfiguration
    @Published var didCopyPreset = false

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

    func exportConfiguration() {
        didCopyPreset = true
        UIPasteboard.general.string = makeSwiftPreset(
            name: fireButtonAnimation.rawValue,
            configuration: configuration
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.didCopyPreset = false
        }
    }

    private func makeSwiftPreset(
        name: String,
        configuration: HapticConfiguration
    ) -> String {
        func format(_ value: Double) -> String {
            String(format: "%.3f", value)
        }

        func format(_ value: Float) -> String {
            String(format: "%.3f", value)
        }

        return """
        static let \(name) = HapticDesign(
            baseIntensity: \(format(configuration.baseIntensity)),
            baseSharpness: \(format(configuration.baseSharpness)),
            hapticStart: \(format(configuration.hapticStart)),
            hapticEnd: \(format(configuration.hapticEnd)),

            intensityPoints: [
        \(configuration.intensityPoints
            .map {
                "        .init(progress: \(format($0.progress)), value: \(format($0.value)))"
            }
            .joined(separator: ",\n"))
            ],

            sharpnessPoints: [
        \(configuration.sharpnessPoints
            .map {
                "        .init(progress: \(format($0.progress)), value: \(format($0.value)))"
            }
            .joined(separator: ",\n"))
            ],

            transientEnabled: \(configuration.transientEnabled),
            transientProgress: \(format(configuration.transientProgress)),
            transientIntensity: \(format(configuration.transientIntensity)),
            transientSharpness: \(format(configuration.transientSharpness))
        )
        """
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

    static let infernoLegacy = HapticConfiguration(
        baseIntensity: 0.85,
        baseSharpness: 0.18,

        hapticStart: 0.04,
        hapticEnd: 0.88,

        intensityPoints: [
            // ~0.08s — flame first appears
            .init(progress: 0.04, value: 0.00),
            // ~0.33s — early ignition
            .init(progress: 0.17, value: 0.12),
            // ~0.67s — flame establishing
            .init(progress: 0.33, value: 0.32),
            // ~1.00s — clearly rising
            .init(progress: 0.50, value: 0.58),
            // ~1.33s — strongest visual growth
            .init(progress: 0.67, value: 0.90),
            // ~1.50s — brief sustained strength
            .init(progress: 0.75, value: 0.78),
            // ~1.67s — orange sequence finishing
            .init(progress: 0.83, value: 0.35),
            // ~1.76s — tactile fade finishes
            .init(progress: 0.88, value: 0.00)
        ],

        sharpnessPoints: [
            // Start very soft
            .init(progress: 0.04, value: 0.00),
            // Flame starts to acquire texture
            .init(progress: 0.25, value: 0.08),
            // More definition as it rises
            .init(progress: 0.45, value: 0.18),
            // Crispest near the visual high point
            .init(progress: 0.67, value: 0.34),
            // Soften during release
            .init(progress: 0.78, value: 0.18),
            .init(progress: 0.88, value: 0.00)
        ],
        transientEnabled: true,
        transientProgress: 0.67,
        transientIntensity: 0.22,
        transientSharpness: 0.38
    )

    static let swirl = HapticConfiguration(
        baseIntensity: 0.72,
        baseSharpness: 0.22,

        hapticStart: 0.04,
        hapticEnd: 0.94,

        intensityPoints: [
            .init(progress: 0.04, value: 0.00),
            .init(progress: 0.15, value: 0.18),
            .init(progress: 0.30, value: 0.42),
            .init(progress: 0.45, value: 0.68),
            .init(progress: 0.60, value: 0.76),
            .init(progress: 0.72, value: 0.66),
            .init(progress: 0.84, value: 0.38),
            .init(progress: 0.94, value: 0.00)
        ],

        sharpnessPoints: [
            .init(progress: 0.04, value: 0.00),
            .init(progress: 0.20, value: 0.10),
            .init(progress: 0.40, value: 0.22),
            .init(progress: 0.58, value: 0.30),
            .init(progress: 0.74, value: 0.22),
            .init(progress: 0.88, value: 0.10),
            .init(progress: 0.94, value: 0.00)
        ],

        transientEnabled: false,
        transientProgress: 0.58,
        transientIntensity: 0.18,
        transientSharpness: 0.30
    )

    static let airstream = HapticConfiguration(
        baseIntensity: 0.78,
        baseSharpness: 0.28,

        hapticStart: 0.03,
        hapticEnd: 0.92,

        intensityPoints: [
            .init(progress: 0.03, value: 0.00),
            // Quick initial engagement
            .init(progress: 0.12, value: 0.24),
            // Multiple colour passes are now active
            .init(progress: 0.24, value: 0.52),
            // Strong tactile body
            .init(progress: 0.40, value: 0.78),
            .init(progress: 0.58, value: 0.82),
            // Start releasing
            .init(progress: 0.72, value: 0.62),
            .init(progress: 0.84, value: 0.30),
            .init(progress: 0.92, value: 0.00)
        ],

        sharpnessPoints: [
            .init(progress: 0.03, value: 0.00),
            .init(progress: 0.16, value: 0.14),
            .init(progress: 0.32, value: 0.30),
            .init(progress: 0.50, value: 0.42),
            .init(progress: 0.66, value: 0.34),
            .init(progress: 0.82, value: 0.16),
            .init(progress: 0.92, value: 0.00)
        ],

        transientEnabled: false,
        transientProgress: 0.22,
        transientIntensity: 0.20,
        transientSharpness: 0.45
    )

}

private extension FireButtonAnimationType {

    var duration: TimeInterval {
        switch self {
        case .fireRising:
            1.17
        case.fireRisingLegacy, .waterSwirl:
            2.0
        case .airstream:
            1.5
        case .none:
            0
        }
    }

    var hapticConfiguration: HapticConfiguration {
        switch self {
        case .fireRising, .none:
                .inferno
        case .fireRisingLegacy:
                .infernoLegacy
        case .waterSwirl:
                .swirl
        case .airstream:
                .airstream
        }
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
