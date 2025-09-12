//
//  RunDBPDebugModeViewController.swift
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

import UIKit
import SwiftUI
import DataBrokerProtectionCore
import DataBrokerProtection_iOS
import BrowserServicesKit
import ContentScopeScripts
import WebKit
import Common
import Combine
import os.log
import PixelKit
import Core
import enum UserScript.UserScriptError

// MARK: - Main View Controller

final class RunDBPDebugModeViewController: UIHostingController<RunDBPDebugModeView> {
    private var viewModel: RunDBPDebugModeViewModel
    
    init() {
        let viewModel = RunDBPDebugModeViewModel()
        let contentView = RunDBPDebugModeView(viewModel: viewModel)
        self.viewModel = viewModel
        super.init(rootView: contentView)
        self.title = "PIR Debug Mode"
        
        setupWebViewButtonObservation()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupWebViewButtonObservation() {
        viewModel.$isWebViewAvailable
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isAvailable in
                self?.updateWebViewButton(isAvailable: isAvailable)
            }
            .store(in: &viewModel.cancellables)
    }
    
    private func updateWebViewButton(isAvailable: Bool) {
        if isAvailable {
            showWebViewButton()
        } else {
            hideWebViewButton()
        }
    }
    
    private func showWebViewButton() {
        let webViewButton = UIBarButtonItem(
            title: "Show WebView",
            style: .plain,
            target: self,
            action: #selector(showWebViewTapped)
        )
        webViewButton.tintColor = .systemBlue
        navigationItem.rightBarButtonItem = webViewButton
    }
    
    private func hideWebViewButton() {
        navigationItem.rightBarButtonItem = nil
    }
    
    @objc private func showWebViewTapped() {
        viewModel.showWebView()
    }
}

// MARK: - SwiftUI View

struct RunDBPDebugModeView: View {
    @ObservedObject var viewModel: RunDBPDebugModeViewModel
    @State private var selectedBrokerJSON: String = ""
    // WebView functionality temporarily removed for minimal scope
    
    var body: some View {
        NavigationView {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 20) {
                    
                    if viewModel.results.isEmpty {
                        inputFormSection
                        brokerSelectionSection
                        operationsSection
                    } else {
                        resultsSection
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .alert(isPresented: $viewModel.showAlert) {
            Alert(
                title: Text(viewModel.alertTitle),
                message: Text(viewModel.alertMessage),
                dismissButton: .default(Text("OK")) {
                    viewModel.showAlert = false
                }
            )
        }
        // WebView sheet removed for minimal scope
    }
    
    private var inputFormSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Profile Information")
                .font(.headline)
            
            TextField("First Name", text: $viewModel.firstName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            TextField("Middle Name", text: $viewModel.middleName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            TextField("Last Name", text: $viewModel.lastName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            TextField("City", text: $viewModel.city)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            TextField("State (2 letters)", text: $viewModel.state)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .onChange(of: viewModel.state) { newValue in
                    if newValue.count > 2 {
                        viewModel.state = String(newValue.prefix(2))
                    }
                }
            
            TextField("Birth Year", text: $viewModel.birthYear)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .keyboardType(.numberPad)
        }
    }
    
    private var brokerSelectionSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            Divider()
            
            Text("Brokers")
                .font(.headline)
            
            if viewModel.brokers.isEmpty {
                Text("Loading brokers...")
                    .foregroundColor(.secondary)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.brokers.sorted(by: { $0.name < $1.name }), id: \.name) { broker in
                            HStack {
                                Text(broker.name)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                
                                Button("View JSON") {
                                    selectedBrokerJSON = broker.toJSONString()
                                }
                                .font(.caption)
                            }
                            .padding(4)
                            .onTapGesture {
                                viewModel.selectedBroker = broker
                                selectedBrokerJSON = broker.toJSONString()
                            }
                            .background(viewModel.selectedBroker?.name == broker.name ? Color.blue.opacity(0.2) : Color.clear)
                            .cornerRadius(6)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .frame(height: 200)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
            }
            
            if !selectedBrokerJSON.isEmpty {
                Text("Broker JSON:")
                    .font(.subheadline)
                    .bold()
                
                ScrollView {
                    Text(selectedBrokerJSON)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(4)
                }
                .frame(height: 150)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
            }
        }
    }
    
    private var operationsSection: some View {
        VStack(spacing: 15) {
            Divider()
            
            if viewModel.isRunning {
                VStack(spacing: 10) {
                    Text(viewModel.currentBrokerName != nil ? "Scanning \(viewModel.currentBrokerName!) (\(viewModel.currentBrokerIndex)/\(viewModel.totalBrokerCount))" : "Scanning...")
                }
            } else {
                VStack(spacing: 10) {
                    Button("Run Selected Broker") {
                        viewModel.runSelectedBroker()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.selectedBroker == nil || !viewModel.hasValidInput)
                    
                    Button("Run All Brokers") {
                        viewModel.runAllBrokers()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!viewModel.hasValidInput)
                }
            }
        }
    }
    
    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("Results")
                    .font(.headline)
                
                Spacer()
                
                Button("Export CSV") {
                    viewModel.exportCSV()
                }
                .buttonStyle(.bordered)
                
                Button("Clear") {
                    viewModel.clearResults()
                }
                .buttonStyle(.bordered)
            }
            
            if viewModel.results.isEmpty {
                Text("No results found")
                    .foregroundColor(.secondary)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(viewModel.results, id: \.id) { result in
                        resultRowView(result: result)
                    }
                }
            }
        }
    }
    
    private func resultRowView(result: ScanResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text(result.extractedProfile.name ?? "No name")
                        .font(.headline)
                    
                    Text(result.extractedProfile.addresses?.map { $0.fullAddress }.joined(separator: ", ") ?? "No address")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let relatives = result.extractedProfile.relatives, !relatives.isEmpty {
                        Text("Relatives: \(relatives.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                if viewModel.optOutInProgress.contains(result.id) {
                    HStack(spacing: 4) {
                        SwiftUI.ProgressView()
                        Text("Opting Out...")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                } else {
                    Button("Opt Out") {
                        viewModel.runOptOut(for: result)
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)
                    .disabled(viewModel.isAnyOptOutInProgress)
                }
            }
            
            Text("Broker: \(result.dataBroker.name)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - View Model

final class RunDBPDebugModeViewModel: ObservableObject {
    @Published var firstName: String = ""
    @Published var middleName: String = ""
    @Published var lastName: String = ""
    @Published var city: String = ""
    @Published var state: String = ""
    @Published var birthYear: String = ""
    @Published var brokers: [DataBroker] = []
    @Published var selectedBroker: DataBroker?
    @Published var results: [ScanResult] = []
    @Published var isRunning: Bool = false
    @Published var currentBrokerName: String?
    @Published var currentBrokerIndex: Int = 0
    @Published var totalBrokerCount: Int = 0
    @Published var showAlert: Bool = false
    @Published var alertTitle: String = ""
    @Published var alertMessage: String = ""
    @Published var optOutInProgress: Set<UUID> = []
    @Published var isWebViewAvailable: Bool = false

    @Published private var currentRunner: BrokerProfileScanSubJobWebRunner?
    private var currentOptOutRunner: BrokerProfileOptOutSubJobWebRunner?

    private var currentWebViewManager: DBPDebugWebViewWindowManager?
    var cancellables = Set<AnyCancellable>()
    private var currentTask: Task<Void, Never>?
    
    private var privacyConfigManager: PrivacyConfigurationManaging {
        return ContentBlocking.shared.privacyConfigurationManager
    }

    private let contentScopeProperties: ContentScopeProperties
    private let emailService: EmailService
    private let captchaService: CaptchaService
    private let fakePixelHandler: EventMapping<DataBrokerProtectionSharedPixels>
    private var pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>?
    private let executionConfig: BrokerJobExecutionConfig
    private let featureFlagger: DBPFeatureFlagging

    var hasValidInput: Bool {
        !firstName.isEmpty && !lastName.isEmpty && !city.isEmpty && !state.isEmpty && !birthYear.isEmpty
    }
    
    var isAnyOptOutInProgress: Bool {
        !optOutInProgress.isEmpty
    }
    
    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }
    
    init() {
        let features = ContentScopeFeatureToggles(
            emailProtection: false,
            emailProtectionIncontextSignup: false,
            credentialsAutofill: false,
            identitiesAutofill: false,
            creditCardsAutofill: false,
            credentialsSaving: false,
            passwordGeneration: false,
            inlineIconCredentials: false,
            thirdPartyCredentialsProvider: false,
            unknownUsernameCategorization: false,
            partialFormSaves: false,
            passwordVariantCategorization: false,
            inputFocusApi: false,
            autocompleteAttributeSupport: false
        )
        
        let sessionKey = UUID().uuidString
        let messageSecret = UUID().uuidString

        self.contentScopeProperties = ContentScopeProperties(
            gpcEnabled: false,
            sessionKey: sessionKey,
            messageSecret: messageSecret,
            featureToggles: features
        )
        
        self.fakePixelHandler = EventMapping { event, _, _, _ in
            print("Debug Pixel: \(event)")
        }
        if let pixelKit = PixelKit.shared {
            self.pixelHandler = DataBrokerProtectionSharedPixelsHandler(pixelKit: pixelKit, platform: .iOS)
        }

        let appDependencies = AppDependencyProvider.shared
        self.featureFlagger = DBPFeatureFlagger(appDependencies: appDependencies)
        let dbpSubscriptionManager = DataBrokerProtectionSubscriptionManager(
            subscriptionManager: appDependencies.subscriptionAuthV1toV2Bridge,
            runTypeProvider: appDependencies.dbpSettings,
            isAuthV2Enabled: appDependencies.isUsingAuthV2
        )
        
        let authenticationManager = DataBrokerProtectionAuthenticationManager(subscriptionManager: dbpSubscriptionManager)
        let dbpSettings = DataBrokerProtectionSettings(defaults: .dbp)
        let backendServicePixels = DefaultDataBrokerProtectionBackendServicePixels(
            pixelHandler: fakePixelHandler,
            settings: dbpSettings
        )
        
        self.emailService = EmailService(
            authenticationManager: authenticationManager,
            settings: dbpSettings,
            servicePixel: backendServicePixels
        )
        
        self.captchaService = CaptchaService(
            authenticationManager: authenticationManager,
            settings: dbpSettings,
            servicePixel: backendServicePixels
        )

        self.executionConfig = BrokerJobExecutionConfig()

        loadBrokers()
    }
    
    private func loadBrokers() {
        Task { @MainActor in
            do {
                let databaseURL = DefaultDataBrokerProtectionDatabaseProvider.databaseFilePath(
                    directoryName: DatabaseConstants.directoryName,
                    fileName: DatabaseConstants.fileName,
                    appGroupIdentifier: nil
                )
                
                let vaultFactory = createDataBrokerProtectionSecureVaultFactory(appGroupName: nil, databaseFileURL: databaseURL)
                let vault = try vaultFactory.makeVault(reporter: nil)
                self.brokers = try vault.fetchAllBrokers()
            } catch {
                showAlert(title: "Error", message: "Failed to load brokers: \(error.localizedDescription)")
            }
        }
    }
    
    func runSelectedBroker() {
        guard let broker = selectedBroker else { return }
        runOperations(brokers: [broker])
    }
    
    func runAllBrokers() {
        runOperations(brokers: brokers)
    }
    
    private func runOperations(brokers: [DataBroker]) {
        guard hasValidInput else { return }
        
        isRunning = true
        results.removeAll()
        updateWebViewAvailability()
        
        currentTask = Task { @MainActor in
            let profile = createProfile()
            let queries = profile.profileQueries
            var allResults: [ScanResult] = []

            self.totalBrokerCount = brokers.count
            
            for (brokerIndex, broker) in brokers.enumerated() {
                self.currentBrokerIndex = brokerIndex + 1
                self.currentBrokerName = broker.name

                for (index, query) in queries.enumerated() {
                    let queryWithId = query.with(id: Int64(index + 1))
                    let brokerProfileQueryData = BrokerProfileQueryData(
                        dataBroker: broker,
                        profileQuery: queryWithId,
                        scanJobData: ScanJobData(brokerId: broker.id ?? 1, profileQueryId: Int64(index + 1), historyEvents: [])
                    )
                    
                    do {
                        let runner = BrokerProfileScanSubJobWebRunner(
                            privacyConfig: privacyConfigManager,
                            prefs: contentScopeProperties,
                            context: brokerProfileQueryData,
                            emailService: emailService,
                            captchaService: captchaService,
                            featureFlagger: featureFlagger,
                            stageDurationCalculator: FakeStageDurationCalculator(),
                            pixelHandler: fakePixelHandler,
                            executionConfig: executionConfig
                        ) { true }

                        self.currentRunner = runner
                        
                        let extractedProfiles = try await runner.scan(brokerProfileQueryData, showWebView: true) { true }
                        for profile in extractedProfiles {
                            let result = ScanResult(
                                dataBroker: broker,
                                profileQuery: queryWithId,
                                extractedProfile: profile
                            )

                            allResults.append(result)
                        }
                        
                    } catch let UserScriptError.failedToLoadJS(jsFile, error) {
                        pixelHandler?.fire(.userScriptLoadJSFailed(jsFile: jsFile, error: error))
                        try? await Task.sleep(interval: 1.0) // give time for the pixel to be sent
                        fatalError("Failed to load JS file \(jsFile): \(error.localizedDescription)")
                    } catch {
                        print("Error scanning \(broker.name): \(error)")
                    }
                    
                    if Task.isCancelled {
                        break
                    }
                }
                
                if Task.isCancelled {
                    break
                }
            }
            
            self.results = allResults
            self.isRunning = false
            self.currentBrokerName = nil
            self.currentBrokerIndex = 0
            self.totalBrokerCount = 0
            
            self.hideWebView()
            self.currentWebViewManager = nil
            self.currentRunner = nil
            self.updateWebViewAvailability()
            
            if allResults.isEmpty {
                showAlert(title: "No Results", message: "No profiles were found during the scan.")
            } else {
                showAlert(title: "Scan Complete", message: "Found \(allResults.count) profile(s).")
            }
        }
    }
    
    func showWebView() {
        if let webViewHandler = getActiveWebViewHandler() {
            if currentWebViewManager == nil {
                currentWebViewManager = DBPDebugWebViewWindowManager(webViewHandler: webViewHandler)
            }
            let title = getWebViewTitle()
            currentWebViewManager?.showWebView(title: title)
        } else if isRunning {
            showAlert(title: "WebView Loading", message: "WebView is not ready yet. Please try again in a moment.")
        } else if !optOutInProgress.isEmpty {
            showAlert(title: "WebView Loading", message: "WebView is not ready yet. Please try again in a moment.")
        } else {
            showAlert(title: "No Active Operation", message: "No scan or opt-out operation is currently running")
        }
    }
    
    private func getActiveWebViewHandler() -> WebViewHandler? {
        if let runner = currentRunner {
            return runner.webViewHandler
        }
        if let optOutRunner = currentOptOutRunner {
            return optOutRunner.webViewHandler
        }
        return nil
    }
    
    private func getWebViewTitle() -> String {
        if let runner = currentRunner {
            let brokerName = runner.context.dataBroker.name
            return "PIR Debug Mode: \(brokerName) (Scan)"
        }
        if let optOutRunner = currentOptOutRunner {
            let brokerName = optOutRunner.context.dataBroker.name
            return "PIR Debug Mode: \(brokerName) (Opt Out)"
        }
        return "PIR Debug Mode"
    }
    
    private func updateWebViewAvailability() {
        isWebViewAvailable = isRunning || !optOutInProgress.isEmpty
    }
    
    func hideWebView() {
        currentWebViewManager?.hideWebView()
    }
    
    func runOptOut(for result: ScanResult) {
        // Add to in-progress set
        optOutInProgress.insert(result.id)
        updateWebViewAvailability()
        
        Task { @MainActor in
            defer {
                optOutInProgress.remove(result.id)
                updateWebViewAvailability()
                self.currentOptOutRunner = nil
                self.hideWebView()
                self.currentWebViewManager = nil
            }
            
            do {
                let brokerProfileQueryData = BrokerProfileQueryData(
                    dataBroker: result.dataBroker,
                    profileQuery: result.profileQuery,
                    scanJobData: ScanJobData(
                        brokerId: result.dataBroker.id ?? 1,
                        profileQueryId: result.profileQuery.id ?? 1,
                        historyEvents: []
                    )
                )
                
                let runner = BrokerProfileOptOutSubJobWebRunner(
                    privacyConfig: privacyConfigManager,
                    prefs: contentScopeProperties,
                    context: brokerProfileQueryData,
                    emailService: emailService,
                    captchaService: captchaService,
                    featureFlagger: featureFlagger,
                    stageCalculator: FakeStageDurationCalculator(),
                    pixelHandler: fakePixelHandler,
                    executionConfig: executionConfig
                ) { true }
                
                self.currentOptOutRunner = runner
                
                try await runner.optOut(
                    profileQuery: brokerProfileQueryData,
                    extractedProfile: result.extractedProfile,
                    showWebView: true
                ) { true }
                
                showAlert(title: "Success", message: "Opt-out process completed for \(result.extractedProfile.name ?? "profile").")
                
            } catch let UserScriptError.failedToLoadJS(jsFile, error) {
                pixelHandler?.fire(.userScriptLoadJSFailed(jsFile: jsFile, error: error))
                try await Task.sleep(interval: 1.0) // give time for the pixel to be sent
                fatalError("Failed to load JS file \(jsFile): \(error.localizedDescription)")
            } catch {
                showAlert(title: "Error", message: "Opt-out failed: \(error.localizedDescription)")
            }
        }
    }
    
    func exportCSV() {
        let csvContent = generateCSV()
        
        let activityVC = UIActivityViewController(
            activityItems: [csvContent],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            
            var topVC = rootVC
            while let presentedVC = topVC.presentedViewController {
                topVC = presentedVC
            }
            
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = topVC.view
                popover.sourceRect = CGRect(x: topVC.view.bounds.midX, y: topVC.view.bounds.midY, width: 0, height: 0)
            }
            
            topVC.present(activityVC, animated: true)
        }
    }
    
    func clearResults() {
        results.removeAll()
    }
    
    private func createProfile() -> DataBrokerProtectionProfile {
        return DataBrokerProtectionProfile(
            names: [DataBrokerProtectionProfile.Name(
                firstName: firstName,
                lastName: lastName,
                middleName: middleName.isEmpty ? nil : middleName
            )],
            addresses: [DataBrokerProtectionProfile.Address(
                city: city,
                state: state
            )],
            phones: [],
            birthYear: Int(birthYear) ?? 1990
        )
    }
    
    private func generateCSV() -> String {
        let headers = ["Name Input", "Age Input", "City Input", "State Input", "Name Scraped", "Address Scraped", "Relatives", "Broker Name"]
        var csvContent = headers.joined(separator: ",") + "\n"
        
        for result in results {
            let row = [
                "\(firstName) \(lastName)",
                birthYear,
                city,
                state,
                result.extractedProfile.name?.replacingOccurrences(of: ",", with: "-") ?? "",
                result.extractedProfile.addresses?.map { $0.fullAddress }.joined(separator: "/").replacingOccurrences(of: ",", with: "-") ?? "",
                result.extractedProfile.relatives?.joined(separator: "/").replacingOccurrences(of: ",", with: "-") ?? "",
                result.dataBroker.name
            ]
            csvContent += row.joined(separator: ",") + "\n"
        }
        
        return csvContent
    }
    
    private func showAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showAlert = true
    }
}

// MARK: - Models

struct ScanResult {
    let id = UUID()
    let dataBroker: DataBroker
    let profileQuery: ProfileQuery
    let extractedProfile: ExtractedProfile
}

// MARK: - Extensions

extension DataBroker {
    func toJSONString() -> String {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let jsonData = try encoder.encode(self)
            return String(data: jsonData, encoding: .utf8) ?? ""
        } catch {
            return "Error encoding broker: \(error.localizedDescription)"
        }
    }
}

// MARK: - Fake Duration Calculator

final class FakeStageDurationCalculator: StageDurationCalculator {
    var attemptId: UUID = UUID()
    var isImmediateOperation: Bool = false
    var tries = 1
    
    func durationSinceLastStage() -> Double { 0.0 }
    func durationSinceStartTime() -> Double { 0.0 }
    func fireOptOutStart() {}
    func setEmailPattern(_ emailPattern: String?) {}
    func fireScanStarted() {}
    func fireOptOutEmailGenerate() {}
    func fireOptOutCaptchaParse() {}
    func fireOptOutCaptchaSend() {}
    func fireOptOutCaptchaSolve() {}
    func fireOptOutSubmit() {}
    func fireOptOutEmailReceive() {}
    func fireOptOutEmailConfirm() {}
    func fireOptOutFillForm() {}
    func fireOptOutValidate() {}
    func fireOptOutSubmitSuccess(tries: Int) {}
    func fireOptOutFailure(tries: Int) {}
    func fireScanSuccess(matchesFound: Int) {}
    func fireScanFailed() {}
    func fireScanError(error: Error) {}
    func setStage(_ stage: Stage) {}
    func setLastActionId(_ actionID: String) {}
    func fireOptOutConditionFound() {}
    func fireOptOutConditionNotFound() {}
    func resetTries() { tries = 1 }
    func incrementTries() { tries += 1 }
}
