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
import DataBrokerProtectionCore
import DataBrokerProtection_iOS
import Core
import Subscription
import PixelKit
import BrowserServicesKit

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
        case dbpMetadata

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
            case .dbpMetadata:
                return "DBP Metadata"
            }
        }

        func cellType(for row: Int) -> CellType {
            switch self {
            case .healthOverview:
                return .rightDetail
            case .database:
                return .subtitle
            case .debugActions:
                return .rightDetail
            case .environment:
                return .subtitle
            case .dbpMetadata:
                return .subtitle
            }
        }
    }

    enum DatabaseRows: Int, CaseIterable {
        case databaseBrowser
        case saveProfile
        case pendingScanJobs
        case pendingOptOutJobs
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
            case .deleteAllData:
                return "Delete All Data"
            }
        }
    }

    enum DebugActionRows: Int, CaseIterable {
        case forceBrokerJSONRefresh
        case runPIRDebugMode
        case runEmailConfirmationOperations
        case runPendingScans
        case runPendingOptOuts
        case runAllPendingJobs
        case fireWeeklyPixel
        case resetAllPIRNotifications

        var title: String {
            switch self {
            case .forceBrokerJSONRefresh:
                return "Force Broker JSON Refresh"
            case .runPIRDebugMode:
                return "Run PIR Debug Mode"
            case .runEmailConfirmationOperations:
                return "Run email confirmation operations"
            case .runPendingScans:
                return "Run Pending Scans"
            case .runPendingOptOuts:
                return "Run Pending Opt Outs"
            case .runAllPendingJobs:
                return "Run All Pending Jobs"
            case .fireWeeklyPixel:
                return "Test Firing Weekly Pixels"
            case .resetAllPIRNotifications:
                return "Reset All PIR Notifications"
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
    
    enum DBPMetadataRows: Int, CaseIterable {
        case refreshMetadata
        case metadataDisplay
    }

    private weak var databaseDelegate: DBPIOSInterface.DatabaseDelegate?
    private weak var debuggingDelegate: DBPIOSInterface.DebuggingDelegate?
    private weak var runPrerequisitesDelegate: DBPIOSInterface.RunPrerequisitesDelegate?
    private let settings = DataBrokerProtectionSettings(defaults: .dbp)
    private let webUISettings = DataBrokerProtectionWebUIURLSettings(.dbp)
    private let healthOverviewPresenter: HealthOverviewSectionPresenter

    @MainActor private var dbpMetadata: String? {
        didSet {
            tableView.reloadSections(IndexSet(integer: Sections.dbpMetadata.rawValue), with: .none)
        }
    }


    @MainActor private var healthOverviewState: HealthOverviewState = .loading {
        didSet {
            tableView.reloadData()
        }
    }
    
    private struct PendingJobCounts {
        let pendingScans: Int
        let pendingScansDetails: String?
        let pendingOptOuts: Int
        let pendingOptOutsDetails: String?
    }

    @MainActor private var jobCounts: PendingJobCounts = PendingJobCounts(pendingScans: 0,
                                                                          pendingScansDetails: nil,
                                                                          pendingOptOuts: 0,
                                                                          pendingOptOutsDetails: nil) {
        didSet {
            tableView.reloadData()
        }
    }
    
    @MainActor private var jobExecutionState: JobExecutionState = .idle {
        didSet {
            handleJobExecutionStateChange(from: oldValue, to: jobExecutionState)
            tableView.reloadData()
        }
    }
    
    private var jobCountRefreshTimer: Timer?
    private let webViewWindowHelper = PIRDebugWebViewWindowHelper()

    private var healthOverviewRows: [HealthOverviewRowViewModel] {
        healthOverviewPresenter.rows(for: healthOverviewState)
    }
    
    enum JobExecutionState: Equatable {
        case idle
        case running
        case failed(error: String)
    }
    

    // MARK: Lifecycle

    required init?(coder: NSCoder,
                   databaseDelegate: DBPIOSInterface.DatabaseDelegate?,
                   debuggingDelegate: DBPIOSInterface.DebuggingDelegate?,
                   runPrequisitesDelegate: DBPIOSInterface.RunPrerequisitesDelegate?) {
        self.databaseDelegate = databaseDelegate
        self.debuggingDelegate = debuggingDelegate
        self.runPrerequisitesDelegate = runPrequisitesDelegate
        self.healthOverviewPresenter = HealthOverviewSectionPresenter(runPrerequisitesDelegate: runPrequisitesDelegate,
                                                                      debuggingDelegate: debuggingDelegate,
                                                                      databaseDelegate: databaseDelegate)

        super.init(coder: coder)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadHealthOverview()
        loadJobCounts()
        refreshMetadata()

        // Check the manager state when entering the debug screen, since PIR could already be running
        if (debuggingDelegate?.isRunningJobs ?? false) && jobExecutionState == .idle {
            jobExecutionState = .running
        }
        
        tableView.reloadData()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopJobCountRefreshTimer()
    }

    private func loadHealthOverview() {
        Task {
            let newState = await healthOverviewPresenter.refreshStateIfNeeded()
            await MainActor.run {
                self.healthOverviewState = newState
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
    
    private func handleJobExecutionStateChange(from oldState: JobExecutionState, to newState: JobExecutionState) {
        switch newState {
        case .running:
            startJobCountRefreshTimer()
            showWebViewButton()
        case .idle, .failed:
            stopJobCountRefreshTimer()
            refreshHealthOverviewMetricsIfNeeded()
        }
    }
    
    private func startJobCountRefreshTimer() {
        stopJobCountRefreshTimer()
        jobCountRefreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.loadJobCounts()
            self?.updateWebViewButtonIfNeeded()
            self?.refreshHealthOverviewMetricsIfNeeded()
        }
    }
    
    private func stopJobCountRefreshTimer() {
        jobCountRefreshTimer?.invalidate()
        jobCountRefreshTimer = nil
    }
    
    private func showWebViewButton() {
        guard webViewWindowHelper.isWebViewAvailable else {
            return
        }
        
        let webViewButton = UIBarButtonItem(
            title: "Show WebView",
            style: .plain,
            target: self,
            action: #selector(showWebViewTapped)
        )

        webViewButton.tintColor = .systemBlue
        navigationItem.rightBarButtonItem = webViewButton
    }
    
    private func updateWebViewButtonIfNeeded() {
        guard jobExecutionState == .running else {
            navigationItem.rightBarButtonItem = nil
            return
        }

        if webViewWindowHelper.isWebViewAvailable && navigationItem.rightBarButtonItem == nil {
            showWebViewButton()
        }
    }
    
    @objc private func showWebViewTapped() {
        webViewWindowHelper.showWebView(title: "PIR Debug Mode")
    }
    
    private func calculatePendingJobCounts() async -> PendingJobCounts {
        guard let allData = try? databaseDelegate?.getAllBrokerProfileQueryData() else {
            assertionFailure("Failed to fetch broker profile query data")
            return PendingJobCounts(pendingScans: 0,
                                    pendingScansDetails: nil,
                                    pendingOptOuts: 0,
                                    pendingOptOutsDetails: nil)
        }

        let currentDate = Date()
        let scanEntries = allData
            .filter { $0.profileQuery.deprecated == false }
            .map { ($0.dataBroker.name, $0.scanJobData) }

        let optOutEntries = allData.flatMap { data in
            data.optOutJobData.map { (data.dataBroker.name, $0) }
        }

        let pendingScanEntries = scanEntries.filter { _, job in
            guard !job.isRemovedByUser else { return false }

            if let preferredRunDate = job.preferredRunDate {
                return preferredRunDate <= currentDate
            }

            return false
        }

        let pendingOptOutEntries = optOutEntries.filter { _, job in
            guard !job.isRemovedByUser else { return false }

            if let preferredRunDate = job.preferredRunDate {
                return preferredRunDate <= currentDate
            }

            return true
        }

        let pendingScansDetails = pendingScanEntries.reduce(into: [String: Int]()) { $0[$1.0, default: 0] += 1 }
        let pendingOptOutsDetails = pendingOptOutEntries.reduce(into: [String: Int]()) { $0[$1.0, default: 0] += 1 }

        return PendingJobCounts(
            pendingScans: pendingScanEntries.count,
            pendingScansDetails: HealthOverviewSectionPresenter.string(from: pendingScansDetails),
            pendingOptOuts: pendingOptOutEntries.count,
            pendingOptOutsDetails: HealthOverviewSectionPresenter.string(from: pendingOptOutsDetails)
        )
    }

    private func refreshHealthOverviewMetricsIfNeeded() {
        Task {
            let currentState = await MainActor.run { self.healthOverviewState }
            let newState = await healthOverviewPresenter.refreshStateIfNeeded(from: currentState)
            await MainActor.run {
                self.healthOverviewState = newState
            }
        }
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

        let identifier = section.cellType(for: indexPath.row).rawValue

        func accessoryLabel(for text: String) -> UILabel {
            let label = UILabel()
            label.font = .daxBodyRegular()
            label.textColor = .secondaryLabel
            label.text = text
            label.sizeToFit()
            return label
        }

        func dequeueCell(identifier: String, style: CellType) -> UITableViewCell {
            let cell = tableView.dequeueReusableCell(withIdentifier: identifier, for: indexPath)
            cell.textLabel?.font = .daxBodyRegular()
            cell.textLabel?.textColor = nil
            cell.textLabel?.numberOfLines = 1
            cell.detailTextLabel?.font = .daxBodyRegular()
            cell.detailTextLabel?.textColor = .secondaryLabel
            cell.detailTextLabel?.text = nil
            cell.detailTextLabel?.numberOfLines = 1
            cell.accessoryType = .none
            cell.accessoryView = nil
            return cell
        }

        switch section {
        case .healthOverview:
            let rows = healthOverviewRows
            let rowViewModel = rows[indexPath.row]
            let cell = dequeueCell(identifier: rowViewModel.style.rawValue, style: rowViewModel.style)

            cell.textLabel?.text = rowViewModel.title
            cell.textLabel?.textColor = rowViewModel.textColor
            cell.textLabel?.numberOfLines = 0
            cell.selectionStyle = .none

            switch rowViewModel.style {
            case .rightDetail:
                cell.detailTextLabel?.text = rowViewModel.detail
            case .subtitle:
                cell.detailTextLabel?.numberOfLines = 0
                cell.detailTextLabel?.text = rowViewModel.subtitle
            }

            if let accessoryText = rowViewModel.accessoryText {
                cell.accessoryView = accessoryLabel(for: accessoryText)
            }

            return cell

        case .database:
            let cell = dequeueCell(identifier: identifier, style: section.cellType(for: indexPath.row))

            let row = DatabaseRows(rawValue: indexPath.row)

            cell.textLabel?.text = row?.title
            cell.textLabel?.numberOfLines = 1

            switch row {
            case .pendingScanJobs:
                cell.detailTextLabel?.numberOfLines = 0
                cell.detailTextLabel?.text = jobCounts.pendingScansDetails
                cell.accessoryView = accessoryLabel(for: "\(jobCounts.pendingScans)")
            case .pendingOptOutJobs:
                cell.detailTextLabel?.numberOfLines = 0
                cell.detailTextLabel?.text = jobCounts.pendingOptOutsDetails
                cell.accessoryView = accessoryLabel(for: "\(jobCounts.pendingOptOuts)")
            case .databaseBrowser, .saveProfile:
                cell.detailTextLabel?.text = nil
                cell.accessoryView = nil
            case .deleteAllData:
                cell.textLabel?.textColor = .systemRed
                cell.detailTextLabel?.text = nil
                cell.accessoryView = nil
            case nil:
                break
            }

            return cell

        case .debugActions:
            let cell = dequeueCell(identifier: identifier, style: section.cellType(for: indexPath.row))

            let row = DebugActionRows(rawValue: indexPath.row)
            cell.textLabel?.text = row?.title

            // Show job execution state for pending job actions
            if let row = row, isJobExecutionAction(row) {
                let hasJobs = hasJobsForAction(row)

                switch jobExecutionState {
                case .idle:
                    // Disable cell if no jobs available
                    if !hasJobs {
                        cell.textLabel?.textColor = .systemGray3
                        cell.detailTextLabel?.text = nil
                        cell.selectionStyle = .none
                    } else {
                        cell.textLabel?.textColor = nil
                        cell.detailTextLabel?.text = nil
                        cell.selectionStyle = .default
                    }
                case .running:
                    // Disable all job action rows while running
                    cell.textLabel?.textColor = .systemGray
                    cell.detailTextLabel?.text = "Running..."
                    cell.selectionStyle = .none
                case .failed(let error):
                    cell.textLabel?.textColor = .systemRed
                    cell.detailTextLabel?.text = "Error: \(error)"
                    cell.selectionStyle = .default
                }
            }

            cell.accessoryView = nil
            return cell

        case .environment:
            let cell = dequeueCell(identifier: identifier, style: section.cellType(for: indexPath.row))

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
            case .none:
                break
            }

            cell.accessoryView = nil
            return cell

        case .dbpMetadata:
            let cell = dequeueCell(identifier: identifier, style: section.cellType(for: indexPath.row))

            guard let row = DBPMetadataRows(rawValue: indexPath.row) else { return cell }
            switch row {
            case .refreshMetadata:
                cell.textLabel?.text = "Refresh Metadata"
                cell.textLabel?.textColor = .systemBlue
            case .metadataDisplay:
                cell.textLabel?.font = .monospacedSystemFont(ofSize: 13.0, weight: .regular)
                cell.textLabel?.text = dbpMetadata ?? "Loading..."
                cell.textLabel?.numberOfLines = 0
            }

            cell.accessoryView = nil
            return cell
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Sections(rawValue: section) {
        case .healthOverview: return healthOverviewRows.count
        case .database: return DatabaseRows.allCases.count
        case .debugActions: return DebugActionRows.allCases.count
        case .environment: return EnvironmentRows.allCases.count
        case .dbpMetadata: return DBPMetadataRows.allCases.count
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
            
            // Prevent interaction with job actions if running or no jobs available
            if isJobExecutionAction(row) {
                if jobExecutionState == .running || !hasJobsForAction(row) {
                    return
                }
            }
            
            handleDebugAction(for: row)
        case .environment:
            guard let row = EnvironmentRows(rawValue: indexPath.row) else { return }
            handleEnvironmentAction(for: row)
        case .healthOverview:
            break
        case .dbpMetadata:
            guard let row = DBPMetadataRows(rawValue: indexPath.row) else { return }
            switch row {
            case .refreshMetadata:
                refreshMetadata()
            case .metadataDisplay:
                break
            }
        }

        tableView.deselectRow(at: indexPath, animated: true)
    }


    // MARK: - Debug Action Rows

    private func handleDebugAction(for row: DebugActionRows) {
        switch row {
        case .runPIRDebugMode:
            let debugModeViewController = RunDBPDebugModeViewController()
            self.navigationController?.pushViewController(debugModeViewController, animated: true)
        case .forceBrokerJSONRefresh:
            Task { @MainActor in
                try await debuggingDelegate?.refreshRemoteBrokerJSON()
                tableView.reloadData()
            }
        case .runEmailConfirmationOperations:
            runEmailConfirmationOperations()
        case .runPendingScans:
            runPendingJobs(type: .scheduledScan)
        case .runPendingOptOuts:
            runPendingJobs(type: .optOut)
        case .runAllPendingJobs:
            runPendingJobs(type: .all)
        case .fireWeeklyPixel:
            Task { @MainActor in
                await debuggingDelegate?.fireWeeklyPixels()
                presentAlert(message: "Weekly pixels fired.")
            }
        case .resetAllPIRNotifications:
            debuggingDelegate?.resetAllNotificationStatesForDebug()
            presentAlert(message: "All PIR notification states reset.")
        }
    }
    
    private func runEmailConfirmationOperations() {
        guard jobExecutionState == .idle else {
            presentAlert(title: "Jobs Already Running", message: "Please wait for the current jobs to complete before starting new ones.")
            return
        }

        Task {
            self.jobExecutionState = .running

            do {
                guard let runPrerequisitesDelegate, await runPrerequisitesDelegate.validateRunPrerequisites() else {
                    self.jobExecutionState = .failed(error: "PIR prerequisites not met")
                    return
                }

                try await debuggingDelegate?.runEmailConfirmationJobs()

                self.jobCounts = await calculatePendingJobCounts()
                self.jobExecutionState = .idle
            } catch {
                let errorMessage: String
                if error is CancellationError {
                    errorMessage = "Operation was cancelled"
                } else {
                    errorMessage = error.localizedDescription
                }

                self.jobExecutionState = .failed(error: errorMessage)

                try? await Task.sleep(nanoseconds: 3_000_000_000)
                self.jobExecutionState = .idle
            }
        }
    }
    
    private func runPendingJobs(type: JobType) {
        guard jobExecutionState == .idle else {
            presentAlert(title: "Jobs Already Running", message: "Please wait for the current jobs to complete before starting new ones.")
            return
        }
        
        Task {
            self.jobExecutionState = .running

            do {
                guard let delegate = runPrerequisitesDelegate,
                    await delegate.validateRunPrerequisites() else {
                    self.jobExecutionState = .failed(error: "PIR prerequisites not met")
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
                    self.jobExecutionState = .idle
                    return
                }

                try await runJobsUsingProductionQueue(type: type)
                self.jobCounts = await calculatePendingJobCounts()
                self.jobExecutionState = .idle
            } catch {
                let errorMessage: String
                if error is CancellationError {
                    errorMessage = "Operation was cancelled"
                } else {
                    errorMessage = error.localizedDescription
                }

                self.jobExecutionState = .failed(error: errorMessage)

                try? await Task.sleep(nanoseconds: 3_000_000_000)
                self.jobExecutionState = .idle
            }
        }
    }
    
    private func runJobsUsingProductionQueue(type: JobType) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            let errorHandler: (DataBrokerProtectionJobsErrorCollection?) -> Void = { errors in
                if let errors = errors, !(errors.operationErrors?.isEmpty ?? true) {
                    print("Job execution completed with errors: \(errors)")
                }
            }

            debuggingDelegate?.runScheduledJobs(type: type, errorHandler: errorHandler) {
                continuation.resume()
            }
        }
    }
    
    private func presentAlert(title: String? = nil, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func isJobExecutionAction(_ row: DebugActionRows) -> Bool {
        switch row {
        case .runEmailConfirmationOperations, .runPendingScans, .runPendingOptOuts, .runAllPendingJobs:
            return true
        default:
            return false
        }
    }
    
    private func hasJobsForAction(_ row: DebugActionRows) -> Bool {
        switch row {
        case .runEmailConfirmationOperations:
            return true
        case .runPendingScans:
            return jobCounts.pendingScans > 0
        case .runPendingOptOuts:
            return jobCounts.pendingOptOuts > 0
        case .runAllPendingJobs:
            return jobCounts.pendingScans > 0 || jobCounts.pendingOptOuts > 0
        default:
            return true
        }
    }

    // MARK: - Database Rows

    private func handleDatabaseAction(for row: DatabaseRows) {
        switch row {
        case .databaseBrowser:
            let dbBrowser = DebugDatabaseBrowserViewController(databaseDelegate: databaseDelegate)
            self.navigationController?.pushViewController(dbBrowser, animated: true)
        case .saveProfile:
            let saveProfileViewController = DebugSaveProfileViewController(databaseDelegate: databaseDelegate)
            self.navigationController?.pushViewController(saveProfileViewController, animated: true)
        case .deleteAllData:
            presentDeleteAllDataAlertController()
        case .pendingScanJobs, .pendingOptOutJobs:
            break
        }
    }

    private func presentDeleteAllDataAlertController() {
        let alert = UIAlertController(title: "Delete All PIR Data?", message: "This will remove all data and statistics from the PIR database, and give you a new tester ID.", preferredStyle: .alert)
        alert.addAction(title: "Delete All Data", style: .destructive) { [weak self] in
            try? self?.databaseDelegate?.deleteAllUserProfileData()
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
                  URL(string: value) != nil else {
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
            try? self?.databaseDelegate?.deleteAllUserProfileData()
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
                try await debuggingDelegate?.refreshRemoteBrokerJSON()
                Logger.dataBrokerProtection.log("Successfully checked for broker updates")
            } catch {
                Logger.dataBrokerProtection.error("Failed to check for broker updates: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - DBP Metadata
    
    private func refreshMetadata() {
        Task { @MainActor in
            self.dbpMetadata = await DefaultDBPMetadataCollector().collectMetadata()?.toPrettyPrintedJSON()
        }
    }
}

// MARK: - PIR Debug WebView Window Helper

class PIRDebugWebViewWindowHelper {
    
    var isWebViewAvailable: Bool {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            return false
        }
        
        for window in windowScene.windows {
            if let navController = window.rootViewController as? UINavigationController,
               let title = navController.topViewController?.title,
               title.hasPrefix("PIR Debug Mode") {
                return true
            }
        }
        
        return false
    }
    
    var isWebViewVisible: Bool {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            return false
        }
        
        for window in windowScene.windows {
            if let navController = window.rootViewController as? UINavigationController,
               let title = navController.topViewController?.title,
               title.hasPrefix("PIR Debug Mode") {
                return window.isKeyWindow
            }
        }
        
        return false
    }
    
    func showWebView(title: String = "PIR Debug Mode: Debug Session") {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            return
        }
        
        for window in windowScene.windows {
            if let navController = window.rootViewController as? UINavigationController,
               let topViewController = navController.topViewController,
               let currentTitle = topViewController.title,
               currentTitle.hasPrefix("PIR Debug Mode") {
                
                // Add close button if not already present
                if topViewController.navigationItem.rightBarButtonItem == nil {
                    let closeButton = UIBarButtonItem(
                        title: "Close",
                        style: .done,
                        target: self,
                        action: #selector(closeWebView)
                    )
                    topViewController.navigationItem.rightBarButtonItem = closeButton
                }
                
                // Update title if provided
                topViewController.title = title
                
                window.makeKeyAndVisible()
                break
            }
        }
    }
    
    @objc private func closeWebView() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            return
        }
        
        for window in windowScene.windows {
            if let navController = window.rootViewController as? UINavigationController,
               let title = navController.topViewController?.title,
               title.hasPrefix("PIR Debug Mode") {
                window.isHidden = true
                break
            }
        }
    }
}
