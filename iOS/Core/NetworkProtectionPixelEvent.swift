//
//  NetworkProtectionPixelEvent.swift
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

import Foundation
import PixelKit

/// Native `PixelKitEvent` definitions for the pixels fired by the iOS VPN packet tunnel.
///
/// This is the source of truth for these pixels' wire names as the tunnel migrates from the legacy
/// `Pixel` / `DailyPixel` stack to `PixelKit`. Every case here mirrors a `Pixel.Event` case fired by
/// `NetworkProtectionPacketTunnelProvider`, and `NetworkProtectionPixelEventTests` asserts each
/// `name` equals the current `Pixel.Event` wire name so nothing forks during the migration.
///
/// Nothing fires these events yet — the tunnel call sites move over in a follow-up. `parameters`,
/// `standardParameters` and error passthrough are therefore left at their defaults here and are
/// populated alongside the call-site migration.
public enum NetworkProtectionPixelEvent: PixelKitEvent {

    case networkProtectionActiveUser
    case networkProtectionAdapterEndTemporaryShutdownStateAttemptFailure
    case networkProtectionAdapterEndTemporaryShutdownStateRecoveryFailure
    case networkProtectionAdapterEndTemporaryShutdownStateRecoverySuccess
    case networkProtectionClientFailedToEncodeRegisterKeyRequest
    case networkProtectionClientFailedToFetchRegisteredServers
    case networkProtectionClientFailedToFetchServerList
    case networkProtectionClientFailedToFetchServerStatus
    case networkProtectionClientFailedToParseRegisteredServersResponse
    case networkProtectionClientFailedToParseServerListResponse
    case networkProtectionClientFailedToParseServerStatusResponse
    case networkProtectionClientInvalidAuthToken
    case networkProtectionConnectionFailureLoopDetected
    case networkProtectionConnectionTesterExtendedFailureDetected
    case networkProtectionConnectionTesterExtendedFailureRecovered
    case networkProtectionConnectionTesterFailureDetected
    case networkProtectionConnectionTesterFailureRecovered
    case networkProtectionDisconnected
    case networkProtectionEnableAttemptConnecting
    case networkProtectionEnableAttemptFailure
    case networkProtectionEnableAttemptSuccess
    case networkProtectionFailureRecoveryCompletedHealthy
    case networkProtectionFailureRecoveryCompletedUnhealthy
    case networkProtectionFailureRecoveryFailed
    case networkProtectionFailureRecoveryStarted
    case networkProtectionKeychainDeleteError
    case networkProtectionKeychainErrorFailedToCastKeychainValueToData
    case networkProtectionKeychainReadError
    case networkProtectionKeychainUpdateError
    case networkProtectionKeychainWriteError
    case networkProtectionLatency(quality: String)
    case networkProtectionLatencyError
    case networkProtectionMemoryCritical
    case networkProtectionMemoryWarning
    case networkProtectionNoAccessTokenFoundError
    case networkProtectionPixelStorageSetupFailure
    case networkProtectionRekeyAttempt
    case networkProtectionRekeyCompleted
    case networkProtectionRekeyFailure
    case networkProtectionServerMigrationAttempt
    case networkProtectionServerMigrationAttemptFailure
    case networkProtectionServerMigrationAttemptSuccess
    case networkProtectionTunnelConfigurationCouldNotGetInterfaceAddressRange
    case networkProtectionTunnelConfigurationCouldNotGetPeerHostName
    case networkProtectionTunnelConfigurationCouldNotGetPeerPublicKey
    case networkProtectionTunnelConfigurationCouldNotSelectClosestServer
    case networkProtectionTunnelConfigurationNoServerRegistrationInfo
    case networkProtectionTunnelFailureDetected
    case networkProtectionTunnelFailureRecovered
    case networkProtectionTunnelStartAttempt
    case networkProtectionTunnelStartAttemptOnDemandWithoutAccessToken
    case networkProtectionTunnelStartFailure
    case networkProtectionTunnelStartSuccess
    case networkProtectionTunnelStopAttempt
    case networkProtectionTunnelStopFailure
    case networkProtectionTunnelStopSuccess
    case networkProtectionTunnelUpdateAttempt
    case networkProtectionTunnelUpdateFailure
    case networkProtectionTunnelUpdateSuccess
    case networkProtectionTunnelWakeFailure
    case networkProtectionUnhandledError
    case networkProtectionUnmanagedSubscriptionError
    case networkProtectionVPNAccessRevoked
    case networkProtectionWireguardErrorCannotLocateTunnelFileDescriptor
    case networkProtectionWireguardErrorCannotSetNetworkSettings
    case networkProtectionWireguardErrorCannotSetWireguardConfig
    case networkProtectionWireguardErrorCannotStartWireguardBackend
    case networkProtectionWireguardErrorFailedDNSResolution
    case networkProtectionWireguardErrorInvalidState
    case subscriptionKeychainAccessError

    public var name: String {
        switch self {
        case .networkProtectionActiveUser: return "m_netp_daily_active_d"
        case .networkProtectionAdapterEndTemporaryShutdownStateAttemptFailure: return "m_netp_adapter_end_temporary_shutdown_state_attempt_failure"
        case .networkProtectionAdapterEndTemporaryShutdownStateRecoveryFailure: return "m_netp_adapter_end_temporary_shutdown_state_recovery_failure"
        case .networkProtectionAdapterEndTemporaryShutdownStateRecoverySuccess: return "m_netp_adapter_end_temporary_shutdown_state_recovery_success"
        case .networkProtectionClientFailedToEncodeRegisterKeyRequest: return "m_netp_backend_api_error_encoding_register_request_body_failed"
        case .networkProtectionClientFailedToFetchRegisteredServers: return "m_netp_backend_api_error_failed_to_fetch_registered_servers"
        case .networkProtectionClientFailedToFetchServerList: return "m_netp_backend_api_error_failed_to_fetch_server_list"
        case .networkProtectionClientFailedToFetchServerStatus: return "m_netp_server_migration_failed_to_fetch_status"
        case .networkProtectionClientFailedToParseRegisteredServersResponse: return "m_netp_backend_api_error_parsing_device_registration_response_failed"
        case .networkProtectionClientFailedToParseServerListResponse: return "m_netp_backend_api_error_parsing_server_list_response_failed"
        case .networkProtectionClientFailedToParseServerStatusResponse: return "m_netp_server_migration_failed_to_parse_response"
        case .networkProtectionClientInvalidAuthToken: return "m_netp_backend_api_error_invalid_auth_token"
        case .networkProtectionConnectionFailureLoopDetected: return "m_netp_connection_failure_loop_detected"
        case .networkProtectionConnectionTesterExtendedFailureDetected: return "m_netp_connection_tester_extended_failure"
        case .networkProtectionConnectionTesterExtendedFailureRecovered: return "m_netp_connection_tester_extended_failure_recovered"
        case .networkProtectionConnectionTesterFailureDetected: return "m_netp_connection_tester_failure"
        case .networkProtectionConnectionTesterFailureRecovered: return "m_netp_connection_tester_failure_recovered"
        case .networkProtectionDisconnected: return "m_netp_vpn_disconnect"
        case .networkProtectionEnableAttemptConnecting: return "m_netp_ev_enable_attempt"
        case .networkProtectionEnableAttemptFailure: return "m_netp_ev_enable_attempt_failure"
        case .networkProtectionEnableAttemptSuccess: return "m_netp_ev_enable_attempt_success"
        case .networkProtectionFailureRecoveryCompletedHealthy: return "m_netp_ev_failure_recovery_completed_server_healthy"
        case .networkProtectionFailureRecoveryCompletedUnhealthy: return "m_netp_ev_failure_recovery_completed_server_unhealthy"
        case .networkProtectionFailureRecoveryFailed: return "m_netp_ev_failure_recovery_failed"
        case .networkProtectionFailureRecoveryStarted: return "m_netp_ev_failure_recovery_started"
        case .networkProtectionKeychainDeleteError: return "m_netp_keychain_error_delete_failed"
        case .networkProtectionKeychainErrorFailedToCastKeychainValueToData: return "m_netp_keychain_error_failed_to_cast_keychain_value_to_data"
        case .networkProtectionKeychainReadError: return "m_netp_keychain_error_read_failed"
        case .networkProtectionKeychainUpdateError: return "m_netp_keychain_error_update_failed"
        case .networkProtectionKeychainWriteError: return "m_netp_keychain_error_write_failed"
        case .networkProtectionLatency(let quality): return "m_netp_ev_\(quality)_latency"
        case .networkProtectionLatencyError: return "m_netp_ev_latency_error_d"
        case .networkProtectionMemoryCritical: return "m_netp_vpn_memory_critical"
        case .networkProtectionMemoryWarning: return "m_netp_vpn_memory_warning"
        case .networkProtectionNoAccessTokenFoundError: return "m_netp_no_access_token_found_error"
        case .networkProtectionPixelStorageSetupFailure: return "m_netp_vpn_pixel_storage_setup_failure"
        case .networkProtectionRekeyAttempt: return "m_netp_rekey_attempt"
        case .networkProtectionRekeyCompleted: return "m_netp_rekey_completed"
        case .networkProtectionRekeyFailure: return "m_netp_rekey_failure"
        case .networkProtectionServerMigrationAttempt: return "m_netp_ev_server_migration_attempt"
        case .networkProtectionServerMigrationAttemptFailure: return "m_netp_ev_server_migration_attempt_failed"
        case .networkProtectionServerMigrationAttemptSuccess: return "m_netp_ev_server_migration_attempt_success"
        case .networkProtectionTunnelConfigurationCouldNotGetInterfaceAddressRange: return "m_netp_tunnel_config_error_could_not_get_interface_address_range"
        case .networkProtectionTunnelConfigurationCouldNotGetPeerHostName: return "m_netp_tunnel_config_error_could_not_get_peer_host_name"
        case .networkProtectionTunnelConfigurationCouldNotGetPeerPublicKey: return "m_netp_tunnel_config_error_could_not_get_peer_public_key"
        case .networkProtectionTunnelConfigurationCouldNotSelectClosestServer: return "m_netp_tunnel_config_error_could_not_select_closest_server"
        case .networkProtectionTunnelConfigurationNoServerRegistrationInfo: return "m_netp_tunnel_config_error_no_server_registration_info"
        case .networkProtectionTunnelFailureDetected: return "m_netp_ev_tunnel_failure"
        case .networkProtectionTunnelFailureRecovered: return "m_netp_ev_tunnel_failure_recovered"
        case .networkProtectionTunnelStartAttempt: return "m_netp_tunnel_start_attempt"
        case .networkProtectionTunnelStartAttemptOnDemandWithoutAccessToken: return "m_netp_tunnel_start_attempt_on_demand_without_access_token"
        case .networkProtectionTunnelStartFailure: return "m_netp_tunnel_start_failure"
        case .networkProtectionTunnelStartSuccess: return "m_netp_tunnel_start_success"
        case .networkProtectionTunnelStopAttempt: return "m_netp_tunnel_stop_attempt"
        case .networkProtectionTunnelStopFailure: return "m_netp_tunnel_stop_failure"
        case .networkProtectionTunnelStopSuccess: return "m_netp_tunnel_stop_success"
        case .networkProtectionTunnelUpdateAttempt: return "m_netp_tunnel_update_attempt"
        case .networkProtectionTunnelUpdateFailure: return "m_netp_tunnel_update_failure"
        case .networkProtectionTunnelUpdateSuccess: return "m_netp_tunnel_update_success"
        case .networkProtectionTunnelWakeFailure: return "m_netp_tunnel_wake_failure"
        case .networkProtectionUnhandledError: return "m_netp_unhandled_error"
        case .networkProtectionUnmanagedSubscriptionError: return "m_vpn_access_unmanaged_error"
        case .networkProtectionVPNAccessRevoked: return "m_vpn_access_revoked"
        case .networkProtectionWireguardErrorCannotLocateTunnelFileDescriptor: return "m_netp_wireguard_error_cannot_locate_tunnel_file_descriptor"
        case .networkProtectionWireguardErrorCannotSetNetworkSettings: return "m_netp_wireguard_error_cannot_set_network_settings"
        case .networkProtectionWireguardErrorCannotSetWireguardConfig: return "m_netp_wireguard_error_cannot_set_wireguard_config"
        case .networkProtectionWireguardErrorCannotStartWireguardBackend: return "m_netp_wireguard_error_cannot_start_wireguard_backend"
        case .networkProtectionWireguardErrorFailedDNSResolution: return "m_netp_wireguard_error_failed_dns_resolution"
        case .networkProtectionWireguardErrorInvalidState: return "m_netp_wireguard_error_invalid_state"
        case .subscriptionKeychainAccessError: return "m_privacy-pro_keychain_access_error"
        }
    }

    public var parameters: [String: String]? { nil }

    public var standardParameters: [PixelKitStandardParameter]? { nil }
}
