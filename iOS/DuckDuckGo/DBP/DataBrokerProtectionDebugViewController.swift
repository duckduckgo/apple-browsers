//
//  DataBrokerProtectionDebugViewController.swift
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
import Common
import BackgroundTasks
import DataBrokerProtectionCore
import DataBrokerProtection_iOS
import Core
import Subscription

final class DataBrokerProtectionDebugViewController: UITableViewController {

    enum CellType: String {
        case rightDetail
        case subtitle
    }
    enum Sections: Int, CaseIterable {
        case healthOverview
        case database
        case debugActions
        case environment

        var title: String {
            switch self {
            case .healthOverview:
                return "Health Overview"
            case .database:
                return "Database"
            case .debugActions:
                return "Debug Actions"
            case .environment:
                return "Environment"
            }
        }

        func cellType(for row: Int) -> CellType {
            switch self {
            case .healthOverview:
                return .rightDetail
            case .database:
                if row == DatabaseRows.deviceIdentifier.rawValue {
                    return .subtitle
                } else {
                    return .rightDetail
                }
            case .debugActions:
                return .rightDetail
            case .environment:
                return .subtitle
            }
        }
    }

    enum DatabaseRows: Int, CaseIterable {
        case databaseBrowser
        case saveProfile
        case pendingScanJobs
        case pendingOptOutJobs
        case deviceIdentifier
        case deleteAllData

        var title: String {
            switch self {
            case .databaseBrowser:
                return "Database Browser"
            case .saveProfile:
                return "Save Profile"
            case .pendingScanJobs:
                return "Pending Scans"
            case .pendingOptOutJobs:
                return "Pending Opt Outs"
            case .deviceIdentifier:
#if DEBUG || ALPHA
                return "UUID"
#else
                return "No UUID due to wrong build type"
#endif
            case .deleteAllData:
                return "Delete All Data"
            }
        }
    }

    enum HealthOverviewRows {
        case loading
        case runPrerequisitesNotMet(hasAccount: Bool, hasEntitlement: Bool, hasProfile: Bool)
        case runPrerequisitesMet(jobScheduled: Bool)

        var rowCount: Int {
            switch self {
            case .loading:
                return 1
            case .runPrerequisitesNotMet:
                return 3
            case .runPrerequisitesMet:
                return 1
            }
        }
    }

    enum DebugActionRows: Int, CaseIterable {
        case forceBrokerJSONRefresh
        case runPIRDebugMode
        case runPendingScans
        case runPendingOptOuts
        case runAllPendingJobs

        var title: String {
            switch self {
            case .forceBrokerJSONRefresh:
                return "Force Broker JSON Refresh"
            case .runPIRDebugMode:
                return "Run PIR Debug Mode"
            case .runPendingScans:
                return "Run Pending Scans"
            case .runPendingOptOuts:
                return "Run Pending Opt Outs"
            case .runAllPendingJobs:
                return "Run All Pending Jobs"
            }
        }
    }

    enum EnvironmentRows: Int, CaseIterable {
        case subscriptionEnvironment
        case dbpAPI
        case webURL

        var title: String {
            switch self {
            case .subscriptionEnvironment:
                return "Environment"
            case .dbpAPI:
                return "DBP API Endpoint"
            case .webURL:
                return "Custom Web URL"
            }
        }
    }

    private var manager: DataBrokerProtectionIOSManager
    private let settings = DataBrokerProtectionSettings(defaults: .dbp)
    private let webUISettings = DataBrokerProtectionWebUIURLSettings(.dbp)

    private lazy var brokerUpdater: BrokerJSONServiceProvider? = {
        let databaseURL = DefaultDataBrokerProtectionDatabaseProvider.databaseFilePath(
            directoryName: DatabaseConstants.directoryName,
            fileName: DatabaseConstants.fileName,
            appGroupIdentifier: nil
        )

        let vaultFactory = createDataBrokerProtectionSecureVaultFactory(appGroupName: nil, databaseFileURL: databaseURL)
        guard let vault = try? vaultFactory.makeVault(reporter: nil) else {
            return nil
        }

        let appDependencies = AppDependencyProvider.shared
        let dbpSubscriptionManager = DataBrokerProtectionSubscriptionManager(
            subscriptionManager: appDependencies.subscriptionAuthV1toV2Bridge,
            runTypeProvider: appDependencies.dbpSettings,
            isAuthV2Enabled: appDependencies.isUsingAuthV2
        )

        let authenticationManager = DataBrokerProtectionAuthenticationManager(subscriptionManager: dbpSubscriptionManager)
        let featureFlagger = DBPFeatureFlagger(appDependencies: appDependencies)

        return RemoteBrokerJSONService(featureFlagger: featureFlagger,
                                       settings: self.settings,
                                       vault: vault,
                                       authenticationManager: authenticationManager,
                                       localBrokerProvider: nil)
    }()

    @MainActor private var healthOverview: HealthOverviewRows = .loading {
        didSet {
            tableView.reloadData()
        }
    }
    
    @MainActor private var jobCounts: (pendingScans: Int, pendingOptOuts: Int) = (0, 0) {
        didSet {
            tableView.reloadData()
        }
    }
    
    @MainActor private var jobExecutionState: JobExecutionState = .idle {
        didSet {
            tableView.reloadData()
        }
    }
    
    enum JobExecutionState: Equatable {
        case idle
        case running(type: String, progress: String)
        case completed(message: String)
        case failed(error: String)
    }
    
    // Progress tracking
    private var progressTimer: Timer?
    private var currentJobType: JobType?
    private var initialJobCount: Int = 0

    // MARK: Lifecycle

    required init?(coder: NSCoder) {
        self.manager = DataBrokerProtectionIOSManager.shared!

        super.init(coder: coder)
    }
    
    deinit {
        stopProgressTimer()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadHealthOverview()
        loadJobCounts()
        tableView.reloadData()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopProgressTimer()
    }

    private func loadHealthOverview() {
        Task {
            if await manager.validateRunPrerequisites() {
                let allScheduledTasks = await BGTaskScheduler.shared.pendingTaskRequests()
                let dbpScheduledTasks = allScheduledTasks.filter {
                    $0.identifier == DataBrokerProtectionIOSManager.backgroundJobIdentifier
                }

                self.healthOverview = .runPrerequisitesMet(jobScheduled: !dbpScheduledTasks.isEmpty)
            } else {
                let hasAccount = manager.meetsAuthenticationRunPrequisite
                let hasEntitlement = (try? await manager.meetsEntitlementRunPrequisite) ?? false
                let hasProfile = (try? manager.meetsProfileRunPrequisite) ?? false

                self.healthOverview = .runPrerequisitesNotMet(
                    hasAccount: hasAccount,
                    hasEntitlement: hasEntitlement,
                    hasProfile: hasProfile
                )
            }
        }
    }
    
    private func loadJobCounts() {
        Task {
            let counts = await calculatePendingJobCounts()
            await MainActor.run {
                self.jobCounts = counts
            }
        }
    }
    
    private func calculatePendingJobCounts() async -> (pendingScans: Int, pendingOptOuts: Int) {
        guard let allData = try? manager.database.fetchAllBrokerProfileQueryData() else {
            return (0, 0)
        }
        
        let currentDate = Date()
        let scanJobs = allData
            .filter { $0.profileQuery.deprecated == false }
            .compactMap { $0.scanJobData }

        let optOutJobs = allData.flatMap { $0.optOutJobData }

        let pendingScanJobs = scanJobs.filter { job in
            guard !job.isRemovedByUser else { return false }
            
            if let preferredRunDate = job.preferredRunDate {
                return preferredRunDate <= currentDate
            }

            return false
        }

        let pendingOptOutJobs = optOutJobs.filter { job in
            guard !job.isRemovedByUser else { return false }
            
            if let preferredRunDate = job.preferredRunDate {
                return preferredRunDate <= currentDate
            }

            return true
        }
        
        return (pendingScanJobs.count, pendingOptOutJobs.count)
    }

    // MARK: Table View

    override func numberOfSections(in tableView: UITableView) -> Int {
        return Sections.allCases.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let section = Sections(rawValue: section) else { return nil }
        return section.title
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let section = Sections(rawValue: indexPath.section) else {
            fatalError("Failed to create a Section from index '\(indexPath.section)'")
        }

        let identifier = section.cellType(for: indexPath.row)
        let cell = tableView.dequeueReusableCell(withIdentifier: identifier.rawValue, for: indexPath)

        cell.textLabel?.font = .daxBodyRegular()
        cell.textLabel?.textColor = nil
        cell.detailTextLabel?.text = nil
        cell.detailTextLabel?.font = nil
        cell.accessoryType = .none

        switch section {
        case .database:
            let row = DatabaseRows(rawValue: indexPath.row)
            cell.textLabel?.text = row?.title

            switch row {
            case .databaseBrowser, .saveProfile, nil: break
            case .pendingScanJobs:
                cell.detailTextLabel?.text = "\(jobCounts.pendingScans)"
            case .pendingOptOutJobs:
                cell.detailTextLabel?.text = "\(jobCounts.pendingOptOuts)"
            case .deviceIdentifier:
                cell.detailTextLabel?.font = UIFont.monospacedSystemFont(ofSize: 17, weight: .regular)
                cell.detailTextLabel?.text = DataBrokerProtectionSettings.deviceIdentifier
            case .deleteAllData:
                cell.textLabel?.textColor = .systemRed
            }

        case .healthOverview:
            switch self.healthOverview {
            case .loading: cell.textLabel?.text = "Loading..."
            case .runPrerequisitesNotMet(let hasAccount, let hasEntitlement, let hasProfile):
                if indexPath.row == 0 {
                    cell.textLabel?.text = "Privacy Pro Account"
                    cell.detailTextLabel?.text = hasAccount ? "✅" :"❌"
                } else if indexPath.row == 1 {
                    cell.textLabel?.text = "PIR Entitlement"
                    cell.detailTextLabel?.text = hasEntitlement ? "✅" :"❌"
                } else if indexPath.row == 2 {
                    cell.textLabel?.text = "Profile Saved In DB"
                    cell.detailTextLabel?.text = hasProfile ? "✅" :"❌"
                } else {
                    fatalError("Expected 3 rows for the health overview")
                }
            case .runPrerequisitesMet(let jobScheduled):
                if jobScheduled {
                    cell.textLabel?.text = "✅ PIR will run some time after device is locked and connected to power"
                } else {
#if targetEnvironment(simulator)
                    cell.textLabel?.text = "❌ Background jobs not supported in the simulator"
#else
                    if UIApplication.shared.backgroundRefreshStatus == .available {
                        cell.textLabel?.text = "❌ Restart the app to schedule PIR"
                    } else {
                        cell.textLabel?.text = "❌ Enable \"Background App Refresh\" in the app's privacy settings"
                    }
#endif
                }
            }

        case .debugActions:
            let row = DebugActionRows(rawValue: indexPath.row)
            cell.textLabel?.text = row?.title
            
            // Show job execution progress for pending job actions
            if let row = row, isJobExecutionAction(row) {
                switch jobExecutionState {
                case .idle:
                    cell.detailTextLabel?.text = nil
                    cell.textLabel?.textColor = nil
                case .running(let type, let progress):
                    if isMatchingJobType(row: row, executingType: type) {
                        cell.detailTextLabel?.text = progress
                    } else {
                        cell.detailTextLabel?.text = nil
                        cell.textLabel?.textColor = .systemGray
                    }
                case .completed(let message):
                    if isMatchingJobType(row: row, executingType: nil) {
                        cell.detailTextLabel?.text = message
                    } else {
                        cell.detailTextLabel?.text = nil
                        cell.textLabel?.textColor = nil
                    }
                case .failed(let error):
                    if isMatchingJobType(row: row, executingType: nil) {
                        cell.detailTextLabel?.text = "Error: \(error)"
                        cell.textLabel?.textColor = .systemRed
                    } else {
                        cell.detailTextLabel?.text = nil
                        cell.textLabel?.textColor = nil
                    }
                }
            }

        case .environment:
            let row = EnvironmentRows(rawValue: indexPath.row)
            cell.textLabel?.text = row?.title

            switch row {
            case .subscriptionEnvironment:
                cell.detailTextLabel?.text = settings.selectedEnvironment.rawValue.localizedCapitalized
            case .dbpAPI:
                cell.detailTextLabel?.text = settings.endpointURL.absoluteString
            case .webURL:
                let urlType = webUISettings.selectedURLType
                let customURL = webUISettings.customURL
                var detailText = ""

                if urlType == .production {
                    detailText = "Production: \(webUISettings.productionURL)"
                } else if urlType == .custom, let customURL {
                    detailText = "Custom: \(customURL)"
                } else {
                    detailText = "Unsupported URL type: \(urlType)"
                }

                cell.detailTextLabel?.text = detailText
            default: break
            }
        }

        return cell
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Sections(rawValue: section) {
        case .healthOverview: return self.healthOverview.rowCount
        case .database: return DatabaseRows.allCases.count
        case .debugActions: return DebugActionRows.allCases.count
        case .environment: return EnvironmentRows.allCases.count
        case .none: return 0
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let section = Sections(rawValue: indexPath.section) else { return }

        switch section {
        case .database:
            guard let row = DatabaseRows(rawValue: indexPath.row) else { return }
            handleDatabaseAction(for: row)
        case .debugActions:
            guard let row = DebugActionRows(rawValue: indexPath.row) else { return }
            
            // Prevent starting new job execution if already running
            if isJobExecutionAction(row) && jobExecutionState != .idle {
                return
            }
            
            handleDebugAction(for: row)
        case .environment:
            guard let row = EnvironmentRows(rawValue: indexPath.row) else { return }
            handleEnvironmentAction(for: row)
        case .healthOverview:
            break
        }

        tableView.deselectRow(at: indexPath, animated: true)
    }

    override func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard let section = Sections(rawValue: indexPath.section), section == .database,
              let row = DatabaseRows(rawValue: indexPath.row), row == .deviceIdentifier else {
            return nil
        }

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            let copyAction = UIAction(title: "Copy", image: UIImage(systemName: "doc.on.doc")) { _ in
                UIPasteboard.general.string = DataBrokerProtectionSettings.deviceIdentifier
            }

            return UIMenu(title: "", children: [copyAction])
        }
    }

    // MARK: - Debug Action Rows

    private func handleDebugAction(for row: DebugActionRows) {
        switch row {
        case .runPIRDebugMode:
            let debugModeViewController = RunDBPDebugModeViewController()
            self.navigationController?.pushViewController(debugModeViewController, animated: true)
        case .forceBrokerJSONRefresh:
            Task { @MainActor in
                if let brokerUpdater {
                    try await brokerUpdater.checkForUpdates(skipsLimiter: true)

                    tableView.reloadData()
                } else {
                    assertionFailure("Failed to create broker updater")
                }
            }
        case .runPendingScans:
            runPendingJobs(type: .scheduledScan)
        case .runPendingOptOuts:
            runPendingJobs(type: .optOut)
        case .runAllPendingJobs:
            runPendingJobs(type: .all)
        }
    }
    
    private func runPendingJobs(type: JobType) {
        guard jobExecutionState == .idle else {
            presentAlert(title: "Jobs Already Running", message: "Please wait for the current jobs to complete before starting new ones.")
            return
        }
        
        Task { @MainActor in
            let typeString = jobTypeDisplayName(type)
            self.jobExecutionState = .running(type: typeString, progress: "Starting...")

            do {
                // Validate prerequisites first
                let canRun = await manager.validateRunPrerequisites()
                guard canRun else {
                    await MainActor.run {
                        self.jobExecutionState = .failed(error: "PIR prerequisites not met. Check Health Overview section.")
                    }
                    return
                }
                
                // Get pending job counts before starting
                let initialCounts = await calculatePendingJobCounts()
                let jobCount: Int
                switch type {
                case .scheduledScan: jobCount = initialCounts.pendingScans
                case .optOut: jobCount = initialCounts.pendingOptOuts
                case .all: jobCount = initialCounts.pendingScans + initialCounts.pendingOptOuts
                default: jobCount = 0
                }
                
                guard jobCount > 0 else {
                    self.jobExecutionState = .completed(message: "No pending jobs found")
                    return
                }
                
                // Store initial state for progress tracking
                self.currentJobType = type
                self.initialJobCount = jobCount
                
                let typeString = jobTypeDisplayName(type)
                self.jobExecutionState = .running(type: typeString, progress: "Starting \(jobCount) job(s)...")

                // Start progress timer to track job completion
                self.startProgressTimer()

                // Execute jobs using production queue manager
                try await runJobsUsingProductionQueue(type: type)
                
                // Stop progress timer
                self.stopProgressTimer()
                
                // Refresh job counts after completion
                let finalCounts = await calculatePendingJobCounts()
                self.jobCounts = finalCounts
                self.jobExecutionState = .completed(message: "Completed \(jobCount) job(s)")

                // Auto-reset to idle after 3 seconds
                try await Task.sleep(nanoseconds: 3_000_000_000)
                self.jobExecutionState = .idle

            } catch {
                self.stopProgressTimer()
                self.jobExecutionState = .failed(error: error.localizedDescription)
                
                // Auto-reset to idle after 5 seconds on error
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                self.jobExecutionState = .idle
            }
        }
    }
    
    private func jobTypeDisplayName(_ type: JobType) -> String {
        switch type {
        case .scheduledScan:
            return "Scan Jobs"
        case .optOut:
            return "Opt-Out Jobs"
        case .all:
            return "All Jobs"
        default:
            return "Jobs"
        }
    }
    
    private func runJobsUsingProductionQueue(type: JobType) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            let errorHandler: (DataBrokerProtectionJobsErrorCollection?) -> Void = { errors in
                if let errors = errors, !(errors.operationErrors?.isEmpty ?? true) {
                    // let errorMessage = errors.map { $0.localizedDescription }.joined(separator: ", ")
                    // continuation.resume(throwing: NSError(domain: "JobExecutionError", code: 1, userInfo: [NSLocalizedDescriptionKey: errorMessage]))
                    continuation.resume()
                } else {
                    continuation.resume()
                }
            }

            manager.runScheduledJobs(type: type, errorHandler: errorHandler) {
                continuation.resume()
            }
        }
    }
    
    private func presentAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    private func isJobExecutionAction(_ row: DebugActionRows) -> Bool {
        switch row {
        case .runPendingScans, .runPendingOptOuts, .runAllPendingJobs:
            return true
        default:
            return false
        }
    }
    
    private func isMatchingJobType(row: DebugActionRows, executingType: String?) -> Bool {
        let rowTypeString = jobTypeDisplayName(jobTypeForRow(row))
        return executingType == nil || executingType == rowTypeString
    }
    
    private func jobTypeForRow(_ row: DebugActionRows) -> JobType {
        switch row {
        case .runPendingScans:
            return .scheduledScan
        case .runPendingOptOuts:
            return .optOut
        case .runAllPendingJobs:
            return .all
        default:
            return .all
        }
    }
    
    // MARK: - Progress Timer
    
    private func startProgressTimer() {
        stopProgressTimer() // Ensure no existing timer
        
        progressTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            Task { @MainActor in
                await self.updateJobProgress()
            }
        }
    }
    
    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
        currentJobType = nil
        initialJobCount = 0
    }
    
    @MainActor
    private func updateJobProgress() async {
        guard let jobType = currentJobType, initialJobCount > 0 else { return }
        
        let currentCounts = await calculatePendingJobCounts()
        let remainingJobs = getRemainingJobCount(for: jobType, counts: currentCounts)
        let completedJobs = max(0, initialJobCount - remainingJobs)
        
        let typeString = jobTypeDisplayName(jobType)
        
        // Create informative progress text
        let progressText: String
        if remainingJobs == 0 {
            progressText = "Completing... (\(completedJobs)/\(initialJobCount) done)"
        } else if completedJobs == 0 {
            progressText = "Starting \(initialJobCount) job(s)..."
        } else {
            let percentComplete = Int((Double(completedJobs) / Double(initialJobCount)) * 100)
            progressText = "Running... (\(completedJobs)/\(initialJobCount) completed, \(percentComplete)%)"
        }
        
        // Only update if still in running state
        if case .running = jobExecutionState {
            jobExecutionState = .running(type: typeString, progress: progressText)
        }
    }
    
    private func getRemainingJobCount(for type: JobType, counts: (pendingScans: Int, pendingOptOuts: Int)) -> Int {
        switch type {
        case .scheduledScan:
            return counts.pendingScans
        case .optOut:
            return counts.pendingOptOuts
        case .all:
            return counts.pendingScans + counts.pendingOptOuts
        default:
            return 0
        }
    }

    // MARK: - Database Rows

    private func handleDatabaseAction(for row: DatabaseRows) {
        switch row {
        case .databaseBrowser:
            let dbBrowser = DebugDatabaseBrowserViewController(database: manager.database)
            self.navigationController?.pushViewController(dbBrowser, animated: true)
        case .saveProfile:
            let saveProfileViewController = DebugSaveProfileViewController(database: manager.database)
            self.navigationController?.pushViewController(saveProfileViewController, animated: true)
        case .deleteAllData:
            presentDeleteAllDataAlertController()
        case .deviceIdentifier, .pendingScanJobs, .pendingOptOutJobs:
            break
        }
    }

    private func presentDeleteAllDataAlertController() {
        let alert = UIAlertController(title: "Delete All PIR Data?", message: "This will remove all data and statistics from the PIR database, and give you a new tester ID.", preferredStyle: .alert)
        alert.addAction(title: "Delete All Data", style: .destructive) { [weak self] in
            try? self?.manager.deleteAllData()
            DataBrokerProtectionSettings.incrementDeviceIdentifier()
            self?.loadJobCounts()
            self?.tableView.reloadData()
        }

        alert.addAction(title: "Cancel", style: .cancel)

        present(alert, animated: true)
    }

    // MARK: - Environment Rows

    private func handleEnvironmentAction(for row: EnvironmentRows) {
        switch row {
        case .subscriptionEnvironment:
            let alert = UIAlertController(title: "PIR Environment", message: "The PIR environment can be changed by changing the Subscription environment.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .cancel))
            present(alert, animated: true)
        case .dbpAPI:
            setCustomServiceRoot()
        case .webURL:
            presentWebURLActionSheet()
        }
    }

    private func presentWebURLActionSheet() {
        let actionSheet = UIAlertController(title: "Web URL Options", message: nil, preferredStyle: .actionSheet)

        actionSheet.addAction(UIAlertAction(title: "Use Production URL", style: .default, handler: { [weak self] _ in
            self?.useWebUIProductionURL()
            self?.tableView.reloadData()
        }))

        actionSheet.addAction(UIAlertAction(title: "Use Custom URL", style: .default, handler: { [weak self] _ in
            self?.useWebUICustomURL()
            self?.tableView.reloadData()
        }))

        actionSheet.addAction(UIAlertAction(title: "Set Custom URL", style: .default, handler: { [weak self] _ in
            self?.setWebUICustomURL()
            self?.tableView.reloadData()
        }))

        actionSheet.addAction(UIAlertAction(title: "Reset Custom URL to Production", style: .destructive, handler: { [weak self] _ in
            self?.resetWebUICustomURL()
            self?.tableView.reloadData()
        }))

        actionSheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popoverController = actionSheet.popoverPresentationController {
            if let cell = tableView.cellForRow(at: IndexPath(row: EnvironmentRows.webURL.rawValue, section: Sections.environment.rawValue)) {
                popoverController.sourceView = cell
                popoverController.sourceRect = cell.bounds
            }
        }

        present(actionSheet, animated: true)
    }

    // MARK: - Web UI URL Actions

    private func setWebUICustomURL() {
        let alert = UIAlertController(title: "Set Custom Web URL",
                                      message: "Enter the full URL",
                                      preferredStyle: .alert)

        alert.addTextField { [weak self] textField in
            // When setting a custom URL, show the existing one if found, otherwise leave it blank
            textField.text = self?.webUISettings.customURL
        }

        let saveAction = UIAlertAction(title: "Save", style: .default) { [weak self, weak alert] _ in
            guard let textField = alert?.textFields?.first,
                  let value = textField.text,
                  let url = URL(string: value), url.isValid else {
                return
            }
            self?.webUISettings.setCustomURL(value)
            self?.webUISettings.setURLType(.custom)
            self?.tableView.reloadData()
        }

        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)

        alert.addAction(saveAction)
        alert.addAction(cancelAction)

        present(alert, animated: true)
    }

    private func resetWebUICustomURL() {
        webUISettings.setURLType(.production)
        webUISettings.setCustomURL(webUISettings.productionURL)
    }

    private func useWebUIProductionURL() {
        webUISettings.setURLType(.production)
    }

    private func useWebUICustomURL() {
        webUISettings.setURLType(.custom)
        webUISettings.setCustomURL(webUISettings.productionURL)
    }

    // MARK: - DBP API Actions

    private func setCustomServiceRoot() {
        let alert = UIAlertController(title: "Set Custom DBP API Service Root",
                                      message: "Enter the base URL for the DBP API. This value is only applied when using the staging environment. Leave empty to reset to default.\n\n⚠️ Please reopen PIR and trigger a new scan for the changes to show up.",
                                      preferredStyle: .alert)

        alert.addTextField { textField in
            textField.text = self.settings.serviceRoot
        }

        let saveAction = UIAlertAction(title: "Save", style: .default) { [weak self, weak alert] _ in
            guard let textField = alert?.textFields?.first,
                  let value = textField.text else {
                return
            }

            self?.settings.serviceRoot = value
            try? self?.manager.deleteAllData()
            self?.forceBrokerJSONFilesUpdate()
            self?.tableView.reloadData()
        }

        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)

        alert.addAction(saveAction)
        alert.addAction(cancelAction)

        present(alert, animated: true)
    }
    
    // MARK: - Remote Broker JSON Service Usage

    private func forceBrokerJSONFilesUpdate() {
        Task {
            settings.resetBrokerDeliveryData()

            do {
                try await brokerUpdater?.checkForUpdates(skipsLimiter: true)
                Logger.dataBrokerProtection.log("Successfully checked for broker updates")
            } catch {
                Logger.dataBrokerProtection.error("Failed to check for broker updates: \(error.localizedDescription)")
            }
        }
    }
}

extension URL {
    var isValid: Bool {
        return scheme != nil && host != nil
    }
}
