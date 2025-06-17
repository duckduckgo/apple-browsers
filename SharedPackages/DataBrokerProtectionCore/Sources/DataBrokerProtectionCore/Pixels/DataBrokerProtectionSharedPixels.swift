//
//  DataBrokerProtectionSharedPixels.swift
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

import Foundation
import PixelKit
import Common

public enum ErrorCategory: Equatable {
    case networkError
    case validationError
    case clientError(httpCode: Int)
    case serverError(httpCode: Int)
    case databaseError(domain: String, code: Int)
    case unclassified

    public var toString: String {
        switch self {
        case .networkError: return "network-error"
        case .validationError: return "validation-error"
        case .unclassified: return "unclassified"
        case .clientError(let httpCode): return "client-error-\(httpCode)"
        case .serverError(let httpCode): return "server-error-\(httpCode)"
        case .databaseError(let domain, let code): return "database-error-\(domain)-\(code)"
        }
    }
}

public enum DataBrokerProtectionSharedPixels {

    public struct Consts {
        public static let dataBrokerParamKey = "data_broker"
        public static let dataBrokerVersionKey = "broker_version"
        public static let appVersionParamKey = "app_version"
        public static let attemptIdParamKey = "attempt_id"
        public static let durationParamKey = "duration"
        public static let bundleIDParamKey = "bundle_id"
        public static let vpnConnectionStateParamKey = "vpn_connection_state"
        public static let vpnBypassStatusParamKey = "vpn_bypass"
        public static let stageKey = "stage"
        public static let matchesFoundKey = "num_found"
        public static let triesKey = "tries"
        public static let errorCategoryKey = "error_category"
        public static let errorDetailsKey = "error_details"
        public static let errorDomainKey = "error_domain"
        public static let pattern = "pattern"
        public static let isParent = "is_parent"
        public static let actionIDKey = "action_id"
        public static let hadNewMatch = "had_new_match"
        public static let hadReAppereance = "had_re-appearance"
        public static let scanCoverage = "scan_coverage"
        public static let removals = "removals"
        public static let environmentKey = "environment"
        public static let wasOnWaitlist = "was_on_waitlist"
        public static let httpCode = "http_code"
        public static let backendServiceCallSite = "backend_service_callsite"
        public static let isImmediateOperation = "is_manual_scan"
        public static let durationInMs = "duration_in_ms"
        public static let profileQueries = "profile_queries"
        public static let hasError = "has_error"
        public static let brokerURL = "broker_url"
        public static let numberOfRecordsFound = "num_found"
        public static let numberOfOptOutsInProgress = "num_inprogress"
        public static let numberOfSucessfulOptOuts = "num_optoutsuccess"
        public static let numberOfOptOutsFailure = "num_optoutfailure"
        public static let durationOfFirstOptOut = "duration_firstoptout"
        public static let numberOfNewRecordsFound = "num_new_found"
        public static let numberOfReappereances = "num_reappeared"
        public static let numberOfHiddenFound = "num_hidden_found"
        public static let optOutSubmitSuccessRate = "optout_submit_success_rate"
        public static let childParentRecordDifference = "child-parent-record-difference"
        public static let calculatedOrphanedRecords = "calculated-orphaned-records"
        public static let actionTypeKey = "action_type"
        public static let keystoreField = "keystore_field"

// This should never ever go to production and only exists for internal testing
#if os(iOS)
        public static let deviceIdentifier = "testerId"
        public static let deviceModel = "deviceModel"
#endif
    }

    case httpError(error: Error, code: Int, dataBroker: String, version: String)
    case actionFailedError(error: Error, actionId: String, message: String, dataBroker: String, version: String)
    case otherError(error: Error, dataBroker: String, version: String)
    case databaseError(error: Error, functionOccurredIn: String)
    case cocoaError(error: Error, functionOccurredIn: String)
    case miscError(error: Error, functionOccurredIn: String)
    case secureVaultInitError(error: Error)
    case secureVaultKeyStoreReadError(error: Error, field: String, serviceName: String)
    case secureVaultKeyStoreUpdateError(error: Error)
    case secureVaultError(error: Error)
    case secureVaultDatabaseRecreated
    case failedToOpenDatabase(error: Error)
    case parentChildMatches(parent: String, child: String, value: Int)

// This should never ever go to production due to the deviceID and only exists for internal testing as long as PIR isn't public on iOS
#if os(iOS)
    // Stage Pixels
    case optOutStart(dataBroker: String, attemptId: UUID, deviceID: String)

    // Process Pixels
    case optOutSubmitSuccess(dataBroker: String, attemptId: UUID, duration: Double, tries: Int, emailPattern: String?, vpnConnectionState: String, vpnBypassStatus: String, deviceID: String)
    case optOutSuccess(dataBroker: String, attemptId: UUID, duration: Double, brokerType: DataBrokerHierarchy, vpnConnectionState: String, vpnBypassStatus: String, deviceID: String)
    case optOutFailure(dataBroker: String, dataBrokerVersion: String, attemptId: UUID, duration: Double, stage: String, tries: Int, emailPattern: String?, actionID: String?, vpnConnectionState: String, vpnBypassStatus: String, deviceID: String)

    // Scan/Search pixels
    case scanStarted(dataBroker: String, deviceID: String)
    case scanSuccess(dataBroker: String, matchesFound: Int, duration: Double, tries: Int, isImmediateOperation: Bool, vpnConnectionState: String, vpnBypassStatus: String, deviceID: String)
    case scanFailed(dataBroker: String, dataBrokerVersion: String, duration: Double, tries: Int, isImmediateOperation: Bool, vpnConnectionState: String, vpnBypassStatus: String, deviceID: String)
    case scanError(dataBroker: String, dataBrokerVersion: String, duration: Double, category: String, details: String, isImmediateOperation: Bool, vpnConnectionState: String, vpnBypassStatus: String, deviceID: String)
    case scanStage(dataBroker: String, dataBrokerVersion: String, tries: Int, actionId: String, actionType: String)
#else
    // Stage Pixels
    case optOutStart(dataBroker: String, attemptId: UUID)

    // Process Pixels
    case optOutSubmitSuccess(dataBroker: String, attemptId: UUID, duration: Double, tries: Int, emailPattern: String?, vpnConnectionState: String, vpnBypassStatus: String)
    case optOutSuccess(dataBroker: String, attemptId: UUID, duration: Double, brokerType: DataBrokerHierarchy, vpnConnectionState: String, vpnBypassStatus: String)
    case optOutFailure(dataBroker: String, dataBrokerVersion: String, attemptId: UUID, duration: Double, stage: String, tries: Int, emailPattern: String?, actionID: String?, vpnConnectionState: String, vpnBypassStatus: String)

    // Scan/Search pixels
    case scanSuccess(dataBroker: String, matchesFound: Int, duration: Double, tries: Int, isImmediateOperation: Bool, vpnConnectionState: String, vpnBypassStatus: String)
    case scanFailed(dataBroker: String, dataBrokerVersion: String, duration: Double, tries: Int, isImmediateOperation: Bool, vpnConnectionState: String, vpnBypassStatus: String)
    case scanError(dataBroker: String, dataBrokerVersion: String, duration: Double, category: String, details: String, isImmediateOperation: Bool, vpnConnectionState: String, vpnBypassStatus: String)
    case scanStage(dataBroker: String, dataBrokerVersion: String, tries: Int, actionId: String, actionType: String)
#endif

    // Stage Pixels
    case optOutEmailGenerate(dataBroker: String, attemptId: UUID, duration: Double, dataBrokerVersion: String, tries: Int, actionId: String)
    case optOutCaptchaParse(dataBroker: String, attemptId: UUID, duration: Double, dataBrokerVersion: String, tries: Int, actionId: String)
    case optOutCaptchaSend(dataBroker: String, attemptId: UUID, duration: Double, dataBrokerVersion: String, tries: Int, actionId: String)
    case optOutCaptchaSolve(dataBroker: String, attemptId: UUID, duration: Double, dataBrokerVersion: String, tries: Int, actionId: String)
    case optOutSubmit(dataBroker: String, attemptId: UUID, duration: Double, dataBrokerVersion: String, tries: Int, actionId: String)
    case optOutEmailReceive(dataBroker: String, attemptId: UUID, duration: Double, dataBrokerVersion: String, tries: Int, actionId: String)
    case optOutEmailConfirm(dataBroker: String, attemptId: UUID, duration: Double, dataBrokerVersion: String, tries: Int, actionId: String)
    case optOutValidate(dataBroker: String, attemptId: UUID, duration: Double, dataBrokerVersion: String, tries: Int, actionId: String)
    case optOutFinish(dataBroker: String, attemptId: UUID, duration: Double)
    case optOutFillForm(dataBroker: String, attemptId: UUID, duration: Double, dataBrokerVersion: String, tries: Int, actionId: String)

    // KPIs - engagement
    case dailyActiveUser
    case weeklyActiveUser
    case monthlyActiveUser

    // KPIs - events
    case weeklyReportScanning(hadNewMatch: Bool, hadReAppereance: Bool, scanCoverage: String)
    case weeklyReportRemovals(removals: Int)
    case scanningEventNewMatch
    case scanningEventReAppearance

    // Additional opt out metrics
    case optOutJobAt7DaysConfirmed(dataBroker: String)
    case optOutJobAt7DaysUnconfirmed(dataBroker: String)
    case optOutJobAt14DaysConfirmed(dataBroker: String)
    case optOutJobAt14DaysUnconfirmed(dataBroker: String)
    case optOutJobAt21DaysConfirmed(dataBroker: String)
    case optOutJobAt21DaysUnconfirmed(dataBroker: String)

    // Backend service errors
    case generateEmailHTTPErrorDaily(statusCode: Int, environment: String, wasOnWaitlist: Bool)
    case emptyAccessTokenDaily(environment: String, wasOnWaitlist: Bool, callSite: BackendServiceCallSite)

    // Initial scans pixels
    // https://app.asana.com/0/1204006570077678/1206981742767458/f
    case initialScanTotalDuration(duration: Double, profileQueries: Int)
    case initialScanSiteLoadDuration(duration: Double, hasError: Bool, brokerURL: String)
    case initialScanPostLoadingDuration(duration: Double, hasError: Bool, brokerURL: String)
    case initialScanPreStartDuration(duration: Double)

    // Measure success/failure rate of Personal Information Removal Pixels
    // https://app.asana.com/0/1204006570077678/1206889724879222/f
    case globalMetricsWeeklyStats(profilesFound: Int, optOutsInProgress: Int, successfulOptOuts: Int, failedOptOuts: Int, durationOfFirstOptOut: Int, numberOfNewRecordsFound: Int)
    case globalMetricsMonthlyStats(profilesFound: Int, optOutsInProgress: Int, successfulOptOuts: Int, failedOptOuts: Int, durationOfFirstOptOut: Int, numberOfNewRecordsFound: Int)
    case dataBrokerMetricsWeeklyStats(dataBrokerURL: String, profilesFound: Int, optOutsInProgress: Int, successfulOptOuts: Int, failedOptOuts: Int, durationOfFirstOptOut: Int, numberOfNewRecordsFound: Int, numberOfReappereances: Int, numberOfHiddenFound: Int)
    case dataBrokerMetricsMonthlyStats(dataBrokerURL: String, profilesFound: Int, optOutsInProgress: Int, successfulOptOuts: Int, failedOptOuts: Int, durationOfFirstOptOut: Int, numberOfNewRecordsFound: Int, numberOfReappereances: Int)

    // Custom stats
    case customDataBrokerStatsOptoutSubmit(dataBrokerName: String, optOutSubmitSuccessRate: Double)
    case customGlobalStatsOptoutSubmit(optOutSubmitSuccessRate: Double)
    case weeklyChildBrokerOrphanedOptOuts(dataBrokerName: String, childParentRecordDifference: Int, calculatedOrphanedRecords: Int)
}

extension DataBrokerProtectionSharedPixels: PixelKitEvent {
    public var name: String {
        switch self {
        case .parentChildMatches: return "dbp_parent-child-broker-matches"
            // SLO and SLI Pixels: https://app.asana.com/0/1203581873609357/1205337273100857/f
            // Stage Pixels
        case .optOutStart: return "dbp_optout_stage_start"
        case .optOutEmailGenerate: return "dbp_optout_stage_email-generate"
        case .optOutCaptchaParse: return "dbp_optout_stage_captcha-parse"
        case .optOutCaptchaSend: return "dbp_optout_stage_captcha-send"
        case .optOutCaptchaSolve: return "dbp_optout_stage_captcha-solve"
        case .optOutSubmit: return "dbp_optout_stage_submit"
        case .optOutEmailReceive: return "dbp_optout_stage_email-receive"
        case .optOutEmailConfirm: return "dbp_optout_stage_email-confirm"
        case .optOutValidate: return "dbp_optout_stage_validate"
        case .optOutFinish: return "dbp_optout_stage_finish"
        case .optOutFillForm: return "dbp_optout_stage_fill-form"

            // Process Pixels
        case .optOutSubmitSuccess: return "dbp_optout_process_submit-success"
        case .optOutSuccess: return "dbp_optout_process_success"
        case .optOutFailure: return "dbp_optout_process_failure"

            // Scan/Search pixels: https://app.asana.com/0/1203581873609357/1205337273100855/f
#if os(iOS)
        case .scanStarted: return "dbp_scan_started"
#endif
        case .scanSuccess: return "dbp_search_stage_main_status_success"
        case .scanFailed: return "dbp_search_stage_main_status_failure"
        case .scanError: return "dbp_search_stage_main_status_error"
        case .scanStage: return "dbp_scan_stage"

            // Debug Pixels
        case .httpError: return "dbp_data_broker_http_error"
        case .actionFailedError: return "dbp_data_broker_action-failed_error"
        case .otherError: return "dbp_data_broker_other_error"
        case .databaseError: return "dbp_data_broker_database_error"
        case .cocoaError: return "dbp_data_broker_cocoa_error"
        case .miscError: return "dbp_data_broker_misc_client_error"
        case .secureVaultInitError: return "dbp_secure_vault_init_error"
        case .secureVaultKeyStoreReadError: return "dbp_secure_vault_keystore_read_error"
        case .secureVaultKeyStoreUpdateError: return "dbp_secure_vault_keystore_update_error"
        case .secureVaultError: return "dbp_secure_vault_error"
        case .secureVaultDatabaseRecreated: return "dbp_secure_vault_database_recreated"
        case .failedToOpenDatabase: return "dbp_failed-to-open-database_error"

            // KPIs - engagement
        case .dailyActiveUser: return "dbp_engagement_dau"
        case .weeklyActiveUser: return "dbp_engagement_wau"
        case .monthlyActiveUser: return "dbp_engagement_mau"

        case .weeklyReportScanning: return "dbp_event_weekly-report_scanning"
        case .weeklyReportRemovals: return "dbp_event_weekly-report_removals"
        case .scanningEventNewMatch: return "dbp_event_scanning-events_new-match"
        case .scanningEventReAppearance: return "dbp_event_scanning-events_re-appearance"

            // Additional opt out metrics
        case .optOutJobAt7DaysConfirmed: return "dbp_optoutjob_at-7-days_confirmed"
        case .optOutJobAt7DaysUnconfirmed: return "dbp_optoutjob_at-7-days_unconfirmed"
        case .optOutJobAt14DaysConfirmed: return "dbp_optoutjob_at-14-days_confirmed"
        case .optOutJobAt14DaysUnconfirmed: return "dbp_optoutjob_at-14-days_unconfirmed"
        case .optOutJobAt21DaysConfirmed: return "dbp_optoutjob_at-21-days_confirmed"
        case .optOutJobAt21DaysUnconfirmed: return "dbp_optoutjob_at-21-days_unconfirmed"

            // Backend service errors
        case .generateEmailHTTPErrorDaily: return "dbp_service_email-generate-http-error"
        case .emptyAccessTokenDaily: return "dbp_service_empty-auth-token"

            // Initial scans pixels
        case .initialScanTotalDuration: return "dbp_initial_scan_duration"
        case .initialScanSiteLoadDuration: return "dbp_scan_broker_site_loaded"
        case .initialScanPostLoadingDuration: return "dbp_initial_scan_broker_post_loading"
        case .initialScanPreStartDuration: return "dbp_initial_scan_pre_start_duration"

        case .globalMetricsWeeklyStats: return "dbp_weekly_stats"
        case .globalMetricsMonthlyStats: return "dbp_monthly_stats"
        case .dataBrokerMetricsWeeklyStats: return "dbp_databroker_weekly_stats"
        case .dataBrokerMetricsMonthlyStats: return "dbp_databroker_monthly_stats"

            // Various monitoring pixels
        case .customDataBrokerStatsOptoutSubmit: return "dbp_databroker_custom_stats_optoutsubmit"
        case .customGlobalStatsOptoutSubmit: return "dbp_custom_stats_optoutsubmit"
        case .weeklyChildBrokerOrphanedOptOuts: return "dbp_weekly_child-broker_orphaned-optouts"
        }
    }

    public var params: [String: String]? {
        parameters
    }

    public var parameters: [String: String]? {
        switch self {
        case .httpError(_, let code, let dataBroker, let version):
            return ["code": String(code),
                    "dataBroker": dataBroker,
                    "version": version]
        case .actionFailedError(_, let actionId, let message, let dataBroker, let version):
            return ["actionID": actionId,
                    "message": message,
                    "dataBroker": dataBroker,
                    "version": version]
        case .otherError(let error, let dataBroker, let version):
            return ["kind": (error as? DataBrokerProtectionError)?.name ?? "unknown",
                    "dataBroker": dataBroker,
                    "version": version]
        case .databaseError(_, let functionOccurredIn),
                .cocoaError(_, let functionOccurredIn),
                .miscError(_, let functionOccurredIn):
            return ["functionOccurredIn": functionOccurredIn]
        case .parentChildMatches(let parent, let child, let value):
            return ["parent": parent, "child": child, "value": String(value)]
// This should never ever go to production due to the deviceID and only exists for internal testing as long as PIR isn't public on iOS
#if os(iOS)
        case .optOutStart(let dataBroker, let attemptId, let deviceID):
            return [Consts.dataBrokerParamKey: dataBroker, Consts.attemptIdParamKey: attemptId.uuidString, Consts.deviceIdentifier: deviceID, Consts.deviceModel: DataBrokerProtectionSettings.modelName]
#else
        case .optOutStart(let dataBroker, let attemptId):
            return [Consts.dataBrokerParamKey: dataBroker, Consts.attemptIdParamKey: attemptId.uuidString]
#endif
        case .optOutEmailGenerate(let dataBroker, let attemptId, let duration, let dataBrokerVersion, let tries, let actionId),
             .optOutCaptchaParse(let dataBroker, let attemptId, let duration, let dataBrokerVersion, let tries, let actionId),
             .optOutCaptchaSend(let dataBroker, let attemptId, let duration, let dataBrokerVersion, let tries, let actionId),
             .optOutCaptchaSolve(let dataBroker, let attemptId, let duration, let dataBrokerVersion, let tries, let actionId),
             .optOutSubmit(let dataBroker, let attemptId, let duration, let dataBrokerVersion, let tries, let actionId),
             .optOutEmailReceive(let dataBroker, let attemptId, let duration, let dataBrokerVersion, let tries, let actionId),
             .optOutEmailConfirm(let dataBroker, let attemptId, let duration, let dataBrokerVersion, let tries, let actionId),
             .optOutValidate(let dataBroker, let attemptId, let duration, let dataBrokerVersion, let tries, let actionId),
             .optOutFillForm(let dataBroker, let attemptId, let duration, let dataBrokerVersion, let tries, let actionId):
            return [Consts.dataBrokerParamKey: dataBroker,
                    Consts.attemptIdParamKey: attemptId.uuidString,
                    Consts.durationParamKey: String(duration),
                    Consts.dataBrokerVersionKey: dataBrokerVersion,
                    Consts.triesKey: String(tries),
                    Consts.actionIDKey: actionId]
        case .optOutFinish(let dataBroker, let attemptId, let duration):
            return [Consts.dataBrokerParamKey: dataBroker,
                    Consts.attemptIdParamKey: attemptId.uuidString,
                    Consts.durationParamKey: String(duration)]
// This should never ever go to production due to the deviceID and only exists for internal testing as long as PIR isn't public on iOS
#if os(iOS)
        case .optOutSubmitSuccess(let dataBroker, let attemptId, let duration, let tries, let pattern, let vpnConnectionState, let vpnBypassStatus, let deviceID):
            var params = [Consts.dataBrokerParamKey: dataBroker, Consts.attemptIdParamKey: attemptId.uuidString, Consts.durationParamKey: String(duration), Consts.triesKey: String(tries), Consts.vpnConnectionStateParamKey: vpnConnectionState, Consts.vpnBypassStatusParamKey: vpnBypassStatus, Consts.deviceIdentifier: deviceID, Consts.deviceModel: DataBrokerProtectionSettings.modelName]
            if let pattern = pattern {
                params[Consts.pattern] = pattern
            }
            return params
        case .optOutSuccess(let dataBroker, let attemptId, let duration, let type, let vpnConnectionState, let vpnBypassStatus, let deviceID):
            return [Consts.dataBrokerParamKey: dataBroker, Consts.attemptIdParamKey: attemptId.uuidString, Consts.durationParamKey: String(duration), Consts.isParent: String(type.rawValue), Consts.vpnConnectionStateParamKey: vpnConnectionState, Consts.vpnBypassStatusParamKey: vpnBypassStatus, Consts.deviceIdentifier: deviceID, Consts.deviceModel: DataBrokerProtectionSettings.modelName]
        case .optOutFailure(let dataBroker, let dataBrokerVersion, let attemptId, let duration, let stage, let tries, let pattern, let actionID, let vpnConnectionState, let vpnBypassStatus, let deviceID):
            var params = [Consts.dataBrokerParamKey: dataBroker, Consts.dataBrokerVersionKey: dataBrokerVersion, Consts.attemptIdParamKey: attemptId.uuidString, Consts.durationParamKey: String(duration), Consts.stageKey: stage, Consts.triesKey: String(tries), Consts.vpnConnectionStateParamKey: vpnConnectionState, Consts.vpnBypassStatusParamKey: vpnBypassStatus, Consts.deviceIdentifier: deviceID, Consts.deviceModel: DataBrokerProtectionSettings.modelName]
            if let pattern = pattern {
                params[Consts.pattern] = pattern
            }

            if let actionID = actionID {
                params[Consts.actionIDKey] = actionID
            }

            return params
        case .scanStarted(let dataBroker, let deviceID):
            return [Consts.dataBrokerParamKey: dataBroker, Consts.deviceIdentifier: deviceID, Consts.deviceModel: DataBrokerProtectionSettings.modelName]
        case .scanSuccess(let dataBroker, let matchesFound, let duration, let tries, let isImmediateOperation, let vpnConnectionState, let vpnBypassStatus, let deviceID):
            return [Consts.dataBrokerParamKey: dataBroker, Consts.matchesFoundKey: String(matchesFound), Consts.durationParamKey: String(duration), Consts.triesKey: String(tries), Consts.isImmediateOperation: isImmediateOperation.description, Consts.vpnConnectionStateParamKey: vpnConnectionState, Consts.vpnBypassStatusParamKey: vpnBypassStatus, Consts.deviceIdentifier: deviceID, Consts.deviceModel: DataBrokerProtectionSettings.modelName]
        case .scanFailed(let dataBroker, let dataBrokerVersion, let duration, let tries, let isImmediateOperation, let vpnConnectionState, let vpnBypassStatus, let deviceID):
            return [Consts.dataBrokerParamKey: dataBroker, Consts.dataBrokerVersionKey: dataBrokerVersion, Consts.durationParamKey: String(duration), Consts.triesKey: String(tries), Consts.isImmediateOperation: isImmediateOperation.description, Consts.vpnConnectionStateParamKey: vpnConnectionState, Consts.vpnBypassStatusParamKey: vpnBypassStatus, Consts.deviceIdentifier: deviceID, Consts.deviceModel: DataBrokerProtectionSettings.modelName]
        case .scanError(let dataBroker, let dataBrokerVersion, let duration, let category, let details, let isImmediateOperation, let vpnConnectionState, let vpnBypassStatus, let deviceID):
            return [Consts.dataBrokerParamKey: dataBroker, Consts.dataBrokerVersionKey: dataBrokerVersion, Consts.durationParamKey: String(duration), Consts.errorCategoryKey: category, Consts.errorDetailsKey: details, Consts.isImmediateOperation: isImmediateOperation.description, Consts.vpnConnectionStateParamKey: vpnConnectionState, Consts.vpnBypassStatusParamKey: vpnBypassStatus, Consts.deviceIdentifier: deviceID, Consts.deviceModel: DataBrokerProtectionSettings.modelName]
        case .scanStage(let dataBroker, let dataBrokerVersion, let tries, let actionId, let actionType):
            return [Consts.dataBrokerParamKey: dataBroker,
                    Consts.dataBrokerVersionKey: dataBrokerVersion,
                    Consts.triesKey: String(tries),
                    Consts.actionIDKey: actionId,
                    Consts.actionTypeKey: actionType]
#else
        case .optOutSubmitSuccess(let dataBroker, let attemptId, let duration, let tries, let pattern, let vpnConnectionState, let vpnBypassStatus):
            var params = [Consts.dataBrokerParamKey: dataBroker, Consts.attemptIdParamKey: attemptId.uuidString, Consts.durationParamKey: String(duration), Consts.triesKey: String(tries), Consts.vpnConnectionStateParamKey: vpnConnectionState, Consts.vpnBypassStatusParamKey: vpnBypassStatus]
            if let pattern = pattern {
                params[Consts.pattern] = pattern
            }
            return params
        case .optOutSuccess(let dataBroker, let attemptId, let duration, let type, let vpnConnectionState, let vpnBypassStatus):
            return [Consts.dataBrokerParamKey: dataBroker, Consts.attemptIdParamKey: attemptId.uuidString, Consts.durationParamKey: String(duration), Consts.isParent: String(type.rawValue), Consts.vpnConnectionStateParamKey: vpnConnectionState, Consts.vpnBypassStatusParamKey: vpnBypassStatus]
        case .optOutFailure(let dataBroker, let dataBrokerVersion, let attemptId, let duration, let stage, let tries, let pattern, let actionID, let vpnConnectionState, let vpnBypassStatus):
            var params = [Consts.dataBrokerParamKey: dataBroker, Consts.dataBrokerVersionKey: dataBrokerVersion, Consts.attemptIdParamKey: attemptId.uuidString, Consts.durationParamKey: String(duration), Consts.stageKey: stage, Consts.triesKey: String(tries), Consts.vpnConnectionStateParamKey: vpnConnectionState, Consts.vpnBypassStatusParamKey: vpnBypassStatus]
            if let pattern = pattern {
                params[Consts.pattern] = pattern
            }

            if let actionID = actionID {
                params[Consts.actionIDKey] = actionID
            }

            return params
        case .scanSuccess(let dataBroker, let matchesFound, let duration, let tries, let isImmediateOperation, let vpnConnectionState, let vpnBypassStatus):
            return [Consts.dataBrokerParamKey: dataBroker, Consts.matchesFoundKey: String(matchesFound), Consts.durationParamKey: String(duration), Consts.triesKey: String(tries), Consts.isImmediateOperation: isImmediateOperation.description, Consts.vpnConnectionStateParamKey: vpnConnectionState, Consts.vpnBypassStatusParamKey: vpnBypassStatus]
        case .scanFailed(let dataBroker, let dataBrokerVersion, let duration, let tries, let isImmediateOperation, let vpnConnectionState, let vpnBypassStatus):
            return [Consts.dataBrokerParamKey: dataBroker, Consts.dataBrokerVersionKey: dataBrokerVersion, Consts.durationParamKey: String(duration), Consts.triesKey: String(tries), Consts.isImmediateOperation: isImmediateOperation.description, Consts.vpnConnectionStateParamKey: vpnConnectionState, Consts.vpnBypassStatusParamKey: vpnBypassStatus]
        case .scanError(let dataBroker, let dataBrokerVersion, let duration, let category, let details, let isImmediateOperation, let vpnConnectionState, let vpnBypassStatus):
            return [Consts.dataBrokerParamKey: dataBroker, Consts.dataBrokerVersionKey: dataBrokerVersion, Consts.durationParamKey: String(duration), Consts.errorCategoryKey: category, Consts.errorDetailsKey: details, Consts.isImmediateOperation: isImmediateOperation.description, Consts.vpnConnectionStateParamKey: vpnConnectionState, Consts.vpnBypassStatusParamKey: vpnBypassStatus]
        case .scanStage(let dataBroker, let dataBrokerVersion, let tries, let actionId, let actionType):
            return [Consts.dataBrokerParamKey: dataBroker,
                    Consts.dataBrokerVersionKey: dataBrokerVersion,
                    Consts.triesKey: String(tries),
                    Consts.actionIDKey: actionId,
                    Consts.actionTypeKey: actionType]
#endif
        case .weeklyReportScanning(let hadNewMatch, let hadReAppereance, let scanCoverage):
            return [Consts.hadNewMatch: hadNewMatch ? "1" : "0", Consts.hadReAppereance: hadReAppereance ? "1" : "0", Consts.scanCoverage: scanCoverage.description]
        case .weeklyReportRemovals(let removals):
            return [Consts.removals: String(removals)]
        case .optOutJobAt7DaysConfirmed(let dataBroker),
                .optOutJobAt7DaysUnconfirmed(let dataBroker),
                .optOutJobAt14DaysConfirmed(let dataBroker),
                .optOutJobAt14DaysUnconfirmed(let dataBroker),
                .optOutJobAt21DaysConfirmed(let dataBroker),
                .optOutJobAt21DaysUnconfirmed(let dataBroker):
            return [Consts.dataBrokerParamKey: dataBroker]
        case .dailyActiveUser,
                .weeklyActiveUser,
                .monthlyActiveUser,

                .scanningEventNewMatch,
                .scanningEventReAppearance,
                .secureVaultInitError,
                .secureVaultKeyStoreUpdateError,
                .secureVaultError,
                .secureVaultDatabaseRecreated,
                .failedToOpenDatabase:
            return [:]
        case .secureVaultKeyStoreReadError(_, let field, _):
            return [Consts.keystoreField: field]
        case .generateEmailHTTPErrorDaily(let statusCode, let environment, let wasOnWaitlist):
            return [Consts.environmentKey: environment,
                    Consts.httpCode: String(statusCode),
                    Consts.wasOnWaitlist: String(wasOnWaitlist)]
        case .emptyAccessTokenDaily(let environment, let wasOnWaitlist, let backendServiceCallSite):
            return [Consts.environmentKey: environment,
                    Consts.wasOnWaitlist: String(wasOnWaitlist),
                    Consts.backendServiceCallSite: backendServiceCallSite.rawValue]
        case .initialScanTotalDuration(let duration, let profileQueries):
            return [Consts.durationInMs: String(duration), Consts.profileQueries: String(profileQueries)]
        case .initialScanSiteLoadDuration(let duration, let hasError, let brokerURL):
            return [Consts.durationInMs: String(duration), Consts.hasError: hasError.description, Consts.brokerURL: brokerURL]
        case .initialScanPostLoadingDuration(let duration, let hasError, let brokerURL):
            return [Consts.durationInMs: String(duration), Consts.hasError: hasError.description, Consts.brokerURL: brokerURL]
        case .initialScanPreStartDuration(let duration):
            return [Consts.durationInMs: String(duration)]
        case .globalMetricsWeeklyStats(let profilesFound, let optOutsInProgress, let successfulOptOuts, let failedOptOuts, let durationOfFirstOptOut, let numberOfNewRecordsFound),
                        .globalMetricsMonthlyStats(let profilesFound, let optOutsInProgress, let successfulOptOuts, let failedOptOuts, let durationOfFirstOptOut, let numberOfNewRecordsFound):
                    return [Consts.numberOfRecordsFound: String(profilesFound),
                            Consts.numberOfOptOutsInProgress: String(optOutsInProgress),
                            Consts.numberOfSucessfulOptOuts: String(successfulOptOuts),
                            Consts.numberOfOptOutsFailure: String(failedOptOuts),
                            Consts.durationOfFirstOptOut: String(durationOfFirstOptOut),
                            Consts.numberOfNewRecordsFound: String(numberOfNewRecordsFound)]
        case .dataBrokerMetricsWeeklyStats(let dataBrokerURL, let profilesFound, let optOutsInProgress, let successfulOptOuts, let failedOptOuts, let durationOfFirstOptOut, let numberOfNewRecordsFound, let numberOfReappereances, let numberOfHiddenFound):
            return [Consts.dataBrokerParamKey: dataBrokerURL,
                    Consts.numberOfRecordsFound: String(profilesFound),
                    Consts.numberOfOptOutsInProgress: String(optOutsInProgress),
                    Consts.numberOfSucessfulOptOuts: String(successfulOptOuts),
                    Consts.numberOfOptOutsFailure: String(failedOptOuts),
                    Consts.durationOfFirstOptOut: String(durationOfFirstOptOut),
                    Consts.numberOfNewRecordsFound: String(numberOfNewRecordsFound),
                    Consts.numberOfReappereances: String(numberOfReappereances),
                    Consts.numberOfHiddenFound: String(numberOfHiddenFound)]
        case .dataBrokerMetricsMonthlyStats(let dataBrokerURL, let profilesFound, let optOutsInProgress, let successfulOptOuts, let failedOptOuts, let durationOfFirstOptOut, let numberOfNewRecordsFound, let numberOfReappereances):
                   return [Consts.dataBrokerParamKey: dataBrokerURL,
                           Consts.numberOfRecordsFound: String(profilesFound),
                           Consts.numberOfOptOutsInProgress: String(optOutsInProgress),
                           Consts.numberOfSucessfulOptOuts: String(successfulOptOuts),
                           Consts.numberOfOptOutsFailure: String(failedOptOuts),
                           Consts.durationOfFirstOptOut: String(durationOfFirstOptOut),
                           Consts.numberOfNewRecordsFound: String(numberOfNewRecordsFound),
                           Consts.numberOfReappereances: String(numberOfReappereances)]
        case .customDataBrokerStatsOptoutSubmit(let dataBrokerName, let optOutSubmitSuccessRate):
            return [Consts.dataBrokerParamKey: dataBrokerName,
                    Consts.optOutSubmitSuccessRate: String(optOutSubmitSuccessRate)]
        case .customGlobalStatsOptoutSubmit(let optOutSubmitSuccessRate):
            return [Consts.optOutSubmitSuccessRate: String(optOutSubmitSuccessRate)]
        case .weeklyChildBrokerOrphanedOptOuts(let dataBrokerName, let childParentRecordDifference, let calculatedOrphanedRecords):
            return [Consts.dataBrokerParamKey: dataBrokerName,
                    Consts.childParentRecordDifference: String(childParentRecordDifference),
                    Consts.calculatedOrphanedRecords: String(calculatedOrphanedRecords)]
        }
    }
}

public class DataBrokerProtectionSharedPixelsHandler: EventMapping<DataBrokerProtectionSharedPixels> {

    public enum Platform {
        case macOS
        case iOS

        var pixelNamePrefix: String {
            switch self {
            case .macOS: return "m_mac_"
            case .iOS: return "m_ios_"
            }
        }
    }

    let pixelKit: PixelKit
    let platform: Platform

    public init(pixelKit: PixelKit, platform: Platform) {
        self.pixelKit = pixelKit
        self.platform = platform
        super.init { _, _, _, _ in
        }

        self.eventMapper = { event, _, _, _ in
            switch event {
            case .generateEmailHTTPErrorDaily:
                self.pixelKit.fire(event, frequency: .legacyDaily, withNamePrefix: platform.pixelNamePrefix)
            case .emptyAccessTokenDaily:
                self.pixelKit.fire(event, frequency: .legacyDaily, withNamePrefix: platform.pixelNamePrefix)
            case .secureVaultDatabaseRecreated:
                self.pixelKit.fire(event, frequency: .dailyAndCount, withNamePrefix: platform.pixelNamePrefix)
            case .httpError(let error, _, _, _),
                    .actionFailedError(let error, _, _, _, _),
                    .otherError(let error, _, _):
                self.pixelKit.fire(DebugEvent(event, error: error), frequency: .dailyAndCount, withNamePrefix: platform.pixelNamePrefix)
            case .databaseError(let error, _),
                    .cocoaError(let error, _),
                    .miscError(let error, _):
                self.pixelKit.fire(DebugEvent(event, error: error), frequency: .dailyAndCount, withNamePrefix: platform.pixelNamePrefix)
            case .secureVaultInitError(let error),
                    .secureVaultError(let error),
                    .secureVaultKeyStoreReadError(let error, _, _),
                    .secureVaultKeyStoreUpdateError(let error),
                    .failedToOpenDatabase(let error):
                self.pixelKit.fire(DebugEvent(event, error: error), frequency: .dailyAndStandard, withNamePrefix: platform.pixelNamePrefix)
            case .parentChildMatches,
                    .optOutStart,
                    .optOutEmailGenerate,
                    .optOutCaptchaParse,
                    .optOutCaptchaSend,
                    .optOutCaptchaSolve,
                    .optOutSubmit,
                    .optOutEmailReceive,
                    .optOutEmailConfirm,
                    .optOutValidate,
                    .optOutFinish,
                    .optOutSubmitSuccess,
                    .optOutFillForm,
                    .optOutSuccess,
                    .optOutFailure,
                    .scanSuccess,
                    .scanFailed,
                    .scanError,
                    .scanStage,
                    .dailyActiveUser,
                    .weeklyActiveUser,
                    .monthlyActiveUser,
                    .weeklyReportScanning,
                    .weeklyReportRemovals,
                    .optOutJobAt7DaysConfirmed,
                    .optOutJobAt7DaysUnconfirmed,
                    .optOutJobAt14DaysConfirmed,
                    .optOutJobAt14DaysUnconfirmed,
                    .optOutJobAt21DaysConfirmed,
                    .optOutJobAt21DaysUnconfirmed,
                    .scanningEventNewMatch,
                    .scanningEventReAppearance,
                    .initialScanTotalDuration,
                    .initialScanSiteLoadDuration,
                    .initialScanPostLoadingDuration,
                    .initialScanPreStartDuration,
                    .globalMetricsWeeklyStats,
                    .globalMetricsMonthlyStats,
                    .dataBrokerMetricsWeeklyStats,
                    .dataBrokerMetricsMonthlyStats,
                    .customDataBrokerStatsOptoutSubmit,
                    .customGlobalStatsOptoutSubmit,
                    .weeklyChildBrokerOrphanedOptOuts:

                self.pixelKit.fire(event, withNamePrefix: platform.pixelNamePrefix)
#if os(iOS)
            case .scanStarted:
                self.pixelKit.fire(event, withNamePrefix: platform.pixelNamePrefix)
#endif

            }
        }
    }

    override init(mapping: @escaping EventMapping<DataBrokerProtectionSharedPixels>.Mapping) {
        fatalError("Use init()")
    }
}
