//
//  PermissionModel.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

import AVFoundation
import Combine
import CoreLocation
import FeatureFlags
import Foundation
import Navigation
import PrivacyConfig
import UserNotifications
import WebKit
import os.log

typealias NotificationAuthorizationProvider = @Sendable () async -> UNAuthorizationStatus

final class PermissionModel {

    @PublishedAfter private(set) var permissions = Permissions()
    @PublishedAfter private(set) var authorizationQuery: PermissionAuthorizationQuery?
    /// Set to true when permissions are changed in the Permission Center and a reload is needed
    @PublishedAfter private(set) var permissionsNeedReload = false

    private(set) var authorizationQueries = [PermissionAuthorizationQuery]() {
        didSet {
            authorizationQuery = authorizationQueries.last
        }
    }

    private let permissionManager: PermissionManagerProtocol
    private let geolocationService: GeolocationServiceProtocol
    private let systemPermissionManager: SystemPermissionManagerProtocol
    private let featureFlagger: FeatureFlagger

    /// Holds the set of permissions the user manually removed (to avoid adding them back via updatePermissions)
    private var removedPermissions = Set<PermissionType>()

    weak var webView: WKWebView? {
        didSet {
            guard let webView = webView else { return }
            assert(oldValue == nil)
            self.subscribe(to: webView)
            self.subscribe(to: permissionManager)
        }
    }
    private var cancellables = Set<AnyCancellable>()

    /// Returns the domain for the current webView URL, mapping file URLs to "localhost"
    private var currentDomain: String? {
        guard let url = webView?.url else { return nil }
        return url.isFileURL ? .localhost : url.host
    }

    init(webView: WKWebView? = nil,
         permissionManager: PermissionManagerProtocol,
         geolocationService: GeolocationServiceProtocol = GeolocationService.shared,
         systemPermissionManager: SystemPermissionManagerProtocol = SystemPermissionManager(),
         featureFlagger: FeatureFlagger) {

        self.permissionManager = permissionManager
        self.geolocationService = geolocationService
        self.systemPermissionManager = systemPermissionManager
        self.featureFlagger = featureFlagger
        if let webView {
            self.webView = webView
            self.subscribe(to: webView)
            self.subscribe(to: permissionManager)
        }
    }

    private func subscribe(to webView: WKWebView) {
        if #available(macOS 12, *) {
            webView.publisher(for: \.cameraCaptureState).sink { [weak self] _ in
                self?.updatePermissions()
            }.store(in: &cancellables)
            webView.publisher(for: \.microphoneCaptureState).sink { [weak self] _ in
                self?.updatePermissions()
            }.store(in: &cancellables)
        } // else: will receive mediaCaptureStateDidChange()

        let geolocationProvider = webView.configuration.processPool.geolocationProvider
        geolocationProvider?.isActivePublisher.sink { [weak self] _ in
            self?.updatePermissions()
        }.store(in: &cancellables)
        geolocationProvider?.isPausedPublisher.sink { [weak self] _ in
            self?.updatePermissions()
        }.store(in: &cancellables)
        geolocationProvider?.authorizationStatusPublisher.sink { [weak self] authorizationStatus in
            self?.geolocationAuthorizationStatusDidChange(to: authorizationStatus)
        }.store(in: &cancellables)
    }

    private func subscribe(to permissionManager: PermissionManagerProtocol) {
        permissionManager.permissionPublisher.sink { [weak self, weak permissionManager] value in
            guard let permissionManager else { return }

            self?.permissionManager(permissionManager,
                                    didChangePermanentDecisionFor: value.permissionType,
                                    forDomain: value.domain,
                                    to: value.decision)
        }.store(in: &cancellables)
    }

    private func resetPermissions() {
        webView?.configuration.processPool.geolocationProvider?.reset()
        webView?.revokePermissions([.camera, .microphone])
        for permission in permissions.keys {
            // await permission deactivation and transition to .none
            permissions[permission].willReload()
        }
        authorizationQueries = []
        removedPermissions.removeAll()
        clearPermissionsNeedReload()
    }

    private func updatePermissions() {
        guard let webView = webView else { return }
        for permissionType in PermissionType.permissionsUpdatedExternally {
            // Skip permissions that were explicitly removed by the user
            guard !removedPermissions.contains(permissionType) else { continue }

            switch permissionType {
            case .microphone:
                permissions.microphone.update(with: webView.microphoneState)
            case .camera:
                permissions.camera.update(with: webView.cameraState)
            case .geolocation:
                let authorizationStatus = webView.configuration.processPool.geolocationProvider?.authorizationStatus
                // Geolocation Authorization is queried before checking the System Permission
                // if it is nil means there was no query made,
                // if query was made but System Permission is disabled: switch to Disabled state
                if permissions.geolocation != nil,
                   [.denied, .restricted].contains(authorizationStatus) {
                    permissions.geolocation
                        .systemAuthorizationDenied(systemWide: !geolocationService.locationServicesEnabled())
                } else {
                    let currentState = webView.geolocationState

                    // With new permission view, keep geolocation as active once it's been granted/used
                    // (.active or .inactive means it was granted or actively used)
                    if featureFlagger.isFeatureOn(.newPermissionView),
                       currentState == .none,
                       permissions.geolocation == .active || permissions.geolocation == .inactive {
                        permissions.geolocation = .active
                    } else {
                        permissions.geolocation.update(with: currentState)
                    }
                }
            case .notification, .popups, .externalScheme:
                continue
            }
        }
    }

    private func persistsWhen(permission: PermissionType, domain: String) -> Bool {
        switch permission {
        case .notification:
            return !permissionManager.hasPermissionPersisted(forDomain: domain, permissionType: permission)
                || permissionManager.permission(forDomain: domain, permissionType: permission) != .ask
        default:
            return false
        }
    }

    private func queryAuthorization(for permissions: [PermissionType],
                                    domain: String,
                                    url: URL?,
                                    isSystemPermissionDisabled: Bool = false,
                                    decisionHandler: @escaping (Bool) -> Void) {

        var queryPtr: UnsafeMutableRawPointer?
        let query = PermissionAuthorizationQuery(domain: domain, url: url, permissions: permissions) { [weak self] result in

            let isGranted = (try? result.get())?.granted ?? false

            // change active permissions state for non-deinitialized query
            if case .success = result {
                for permission in permissions {
                    if isGranted {
                        // Remove from removedPermissions so updatePermissions() can track it again
                        self?.removedPermissions.remove(permission)
                        self?.permissions[permission].granted()
                    } else {
                        self?.permissions[permission].denied()
                    }
                }
            }

            if let self,
               let idx = self.authorizationQueries.firstIndex(where: { Unmanaged.passUnretained($0).toOpaque() == queryPtr }) {

                self.authorizationQueries.remove(at: idx)

                if case .success( (let granted, let remember) ) = result {
                    for permission in permissions {
                        // Preserve existing Always Allow/Deny decisions; don't downgrade to Ask
                        let isPersisting = remember == true || persistsWhen(permission: permission, domain: domain)
                        if isPersisting {
                            self.permissionManager.setPermission(granted ? .allow : .deny, forDomain: domain, permissionType: permission)
                        } else if self.featureFlagger.isFeatureOn(.newPermissionView) {
                            // Other permissions: one-time decisions store .ask for permission center visibility
                            self.permissionManager.setPermission(.ask, forDomain: domain, permissionType: permission)
                        }
                    }
                }
            } // else: query has been removed, the decision is being handled on the query deallocation

            decisionHandler(isGranted)
        }
        // "unowned" query reference to be able to use the pointer when the callback is called on query deinit
        queryPtr = Unmanaged.passUnretained(query).toOpaque()

        // When Geolocation queried by a website but System Permission is denied: switch to `disabled`
        // Only apply this behavior when new permission view is disabled (old behavior)
        // When new permission view is enabled, the dialog handles showing the two-step authorization flow
        if !featureFlagger.isFeatureOn(.newPermissionView),
           permissions.contains(.geolocation),
           [.denied, .restricted].contains(self.geolocationService.authorizationStatus)
            || !geolocationService.locationServicesEnabled() {
            self.permissions.geolocation
                .systemAuthorizationDenied(systemWide: !geolocationService.locationServicesEnabled())
        }

        // Set state to .requested so the authorization popover can be shown
        permissions.forEach { self.permissions[$0].authorizationQueried(query, updateQueryIfAlreadyRequested: $0 == .popups) }
        query.isSystemPermissionDisabled = isSystemPermissionDisabled
        authorizationQueries.append(query)
    }

    private func permissionManager(_: PermissionManagerProtocol,
                                   didChangePermanentDecisionFor permissionType: PermissionType,
                                   forDomain domain: String,
                                   to decision: PersistedPermissionDecision) {

        // If Always Allow/Deny for the current host: Grant/Revoke the permission
        guard webView?.url?.host?.droppingWwwPrefix() == domain else { return }

        // If decision changed to "allow", remove from removedPermissions so updatePermissions() can track it again
        if decision == .allow {
            removedPermissions.remove(permissionType)
        }

        switch (decision, self.permissions[permissionType]) {
        case (.deny, .some):
            self.revoke(permissionType)
            fallthrough
        case (.allow, .requested):
            while let query = self.authorizationQueries.first(where: { $0.permissions == [permissionType] }) {
                query.handleDecision(grant: decision == .allow)
            }
        default: break
        }
    }

    // MARK: Pausing/Revoking

    func set(_ permissions: [PermissionType], muted: Bool) {
        webView?.setPermissions(permissions, muted: muted)
    }

    func allow(_ query: PermissionAuthorizationQuery) {
        guard self.authorizationQueries.contains(where: { $0 === query }) else {
            assertionFailure("unexpected Permission state")
            return
        }
        query.handleDecision(grant: true)
    }

    func revoke(_ permission: PermissionType) {
        if let domain = currentDomain,
           case .allow = permissionManager.permission(forDomain: domain, permissionType: permission) {
            permissionManager.setPermission(.ask, forDomain: domain, permissionType: permission)
        }
        switch permission {
        case .camera, .microphone, .geolocation:
            self.permissions[permission].revoke() // await deactivation
            webView?.revokePermissions([permission])

        case .popups, .notification, .externalScheme:
            self.permissions[permission].denied()
        }
    }

    /// Removes a permission completely (revokes and removes from tracking)
    func remove(_ permission: PermissionType) {
        // Track as explicitly removed to prevent re-adding via updatePermissions()
        removedPermissions.insert(permission)

        // First revoke the permission
        switch permission {
        case .camera, .microphone, .geolocation:
            webView?.revokePermissions([permission])
        case .popups, .notification, .externalScheme:
            break
        }

        // Remove from dictionary (will trigger @Published update)
        permissions[permission] = nil

        // Remove from persisted storage
        if let domain = currentDomain {
            permissionManager.removePermission(forDomain: domain, permissionType: permission)
        } else {
            assertionFailure("webView URL should not be nil when removing a permission")
        }
    }

    /// Checks if a permission is granted (either persistently via "Always Allow" or for this session via one-time grant).
    ///
    /// Permission states indicating "granted":
    /// - `.active`: Permission granted and actively in use (e.g., camera streaming, geolocation updating)
    /// - `.inactive`: Permission granted but not currently active (e.g., camera granted but off, notification granted but idle)
    /// - `.paused`: Permission granted and in use but muted (e.g., camera on but muted)
    ///
    /// When user grants permission, it transitions from `.requested` to `.inactive` (see PermissionState.granted()).
    /// For media permissions (camera/mic), WebView tracking then updates to `.active` when used.
    /// For notifications, it stays `.inactive` (no WebView tracking for notification usage).
    ///
    /// This matches the existing pattern in PermissionModel.updatePermissions():
    /// "(.active or .inactive means it was granted or actively used)"
    ///
    /// - Parameters:
    ///   - permission: The permission type to check
    ///   - domain: The domain to check permission for
    /// - Returns: `true` if permission is granted (persistent or session), `false` otherwise
    func isPermissionGranted(_ permission: PermissionType, forDomain domain: String) -> Bool {
        // Check persisted decision first (Always Allow)
        let persistentDecision = permissionManager.permission(forDomain: domain, permissionType: permission)
        if persistentDecision == .allow {
            return true
        }

        // Check runtime/session state (one-time grant for this session)
        // States .active, .inactive, .paused all indicate permission was granted
        let sessionState = permissions[permission]
        switch sessionState {
        case .active, .inactive, .paused:
            return true
        default:
            return false
        }
    }

    /// Marks that permissions were changed and a reload is needed to apply changes
    func setPermissionsNeedReload() {
        permissionsNeedReload = true
    }

    /// Clears the reload flag (called when page reloads)
    func clearPermissionsNeedReload() {
        permissionsNeedReload = false
    }

    // MARK: - WebView delegated methods

    // Called before requestMediaCapturePermissionFor: to validate System Permissions
    func checkUserMediaPermission(for url: URL?, mainFrameURL: URL?, decisionHandler: @escaping (String, Bool) -> Void) {
        // If media capture is denied in the System Preferences, reflect it in the current permissions
        // AVCaptureDevice.authorizationStatus(for:mediaType) is swizzled to determine requested media type
        // otherwise WebView won't call any other delegate methods if System Permission is denied
        var checkedPermissions = Set<PermissionType>()
        AVCaptureDevice.swizzleAuthorizationStatusForMediaType { [weak self] mediaType, authorizationStatus in
            let permission: PermissionType
            // media type for Camera/Microphone can be only determined separately
            switch mediaType {
            case .audio:
                permission = .microphone
            case .video:
                permission = .camera
            default: return
            }
            switch authorizationStatus {
            case .denied, .restricted:
                self?.permissions[permission].systemAuthorizationDenied(systemWide: false)
                AVCaptureDevice.restoreAuthorizationStatusForMediaType()

            case .notDetermined, .authorized:
                checkedPermissions.insert(permission)
                if checkedPermissions == [.camera, .microphone] {
                    AVCaptureDevice.restoreAuthorizationStatusForMediaType()
                }
            @unknown default: break
            }
        }
        decisionHandler(/*salt - seems not used anywhere:*/ "", /*includeSensitiveMediaDeviceDetails:*/ false)
        // make sure to swizzle it back after reasonable interval in case it wasn't called
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            AVCaptureDevice.restoreAuthorizationStatusForMediaType()
        }
    }

    private func shouldGrantPermission(for permissions: [PermissionType], requestedForDomain domain: String) -> Bool? {
        for permission in permissions {
            var grant: PersistedPermissionDecision
            let stored = permissionManager.permission(forDomain: domain, permissionType: permission)
            if case .allow = stored, permission.canPersistGrantedDecision(featureFlagger: featureFlagger) {
                grant = .allow
            } else if case .deny = stored, permission.canPersistDeniedDecision(featureFlagger: featureFlagger) {
                grant = .deny
            } else if let state = self.permissions[permission] {
                switch state {
                // deny if already denied during current page being displayed
                case .denied, .revoking:
                    grant = .deny
                // ask otherwise
                case .disabled, .requested, .active, .inactive, .paused, .reloading:
                    grant = .ask
                }
            } else {
                grant = .ask
            }

            switch grant {
            case .deny:
                // Deny immediately - user explicitly set "Never Allow" for this domain
                // No need to check system permission state
                return false
            case .allow:
                // User has "Always Allow" stored - but check system permission first
                if featureFlagger.isFeatureOn(.newPermissionView), isSystemPermissionDisabled(for: permission) {
                    return nil
                }
            case .ask:
                // if at least one permission is not set: ask
                return nil
            }
        }
        return true
    }

    /// Checks if system-level permission is disabled for the given permission type (uses cached state for sync access)
    private func isSystemPermissionDisabled(for permissionType: PermissionType) -> Bool {
        guard permissionType.requiresSystemPermission else { return false }

        let authState = systemPermissionManager.cachedAuthorizationState(for: permissionType)
        return authState == .denied || authState == .restricted || authState == .systemDisabled
    }

    /// Request user authorization for provided PermissionTypes
    /// The decisionHandler will be called synchronously if there's a permanent (stored) permission granted or denied
    /// If no permanent decision is stored a new AuthorizationQuery will be initialized and published via $authorizationQuery
    func permissions(_ permissions: [PermissionType], requestedForDomain domain: String, url: URL? = nil, decisionHandler: @escaping (Bool) -> Void) {
        guard !permissions.isEmpty else {
            assertionFailure("Unexpected permissions/domain")
            decisionHandler(false)
            return
        }

        let shouldGrant = shouldGrantPermission(for: permissions, requestedForDomain: domain)
        let wrappedDecisionHandler = { [weak self] (isGranted: Bool) in
            decisionHandler(isGranted)
            if isGranted {
                self?.permissionGranted(for: permissions[0])
            }
        }
        switch shouldGrant {
        case .none:
            // Check if this is "app=allow but system=disabled" case
            let isSystemDisabled: Bool = {
                guard let permission = permissions.first,
                      permission.requiresSystemPermission,
                      self.featureFlagger.isFeatureOn(.newPermissionView) else { return false }
                return self.permissionManager.permission(forDomain: domain, permissionType: permission) == .allow
            }()
            self.queryAuthorization(for: permissions, domain: domain, url: url,
                                    isSystemPermissionDisabled: isSystemDisabled,
                                    decisionHandler: wrappedDecisionHandler)
        case .some(true):
            wrappedDecisionHandler(true)
        case .some(false):
            wrappedDecisionHandler(false)
            for permission in permissions {
                self.permissions[permission].denied()
            }
        }
    }
    @available(macOS 12.0, *)
    func permissions(_ permissions: [PermissionType], requestedForDomain domain: String, url: URL? = nil, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        self.permissions(permissions, requestedForDomain: domain, url: url) { isGranted in
            decisionHandler(isGranted ? .grant : .deny)
        }
    }

    private func permissionGranted(for permission: PermissionType) {
        // handle special permission granted for permission without `active` (used) state
        switch permission {
        case .externalScheme:
            self.permissions[permission].externalSchemeOpened()
        case .popups:
            self.permissions[permission].popupOpened(nextQuery: authorizationQueries.first(where: { $0.permissions.contains(.popups) }))
        case .camera, .microphone, .geolocation, .notification:
            // permission usage activated
            break
        }

    }

    /// Request user authorization for provided PermissionTypes
    /// Same as `permissions(_:requestedForDomain:url:decisionHandler:)` with a result returned using a `Future`
    /// Use `await future.get()` for async/await syntax
    func request(_ permissions: [PermissionType], forDomain domain: String, url: URL? = nil) -> Future<Bool, Never> {
        Future { fulfill in
            self.permissions(permissions, requestedForDomain: domain, url: url) { isGranted in
                fulfill(.success(isGranted))
            }
        }
    }

    func mediaCaptureStateDidChange() {
        updatePermissions()
    }

    func tabDidStartNavigation() {
        resetPermissions()
    }

    func geolocationAuthorizationStatusDidChange(to authorizationStatus: CLAuthorizationStatus) {
        switch (authorizationStatus, geolocationService.locationServicesEnabled()) {
        case (.authorized, true), (.authorizedAlways, true):
            // if a website awaits a Query Authorization while System Permission is disabled
            // show the Authorization Popover
            if let query = self.authorizationQueries.first(where: { $0.permissions.contains(.geolocation) }),
               case .disabled = self.permissions.geolocation {
                // switch to `requested` state
                self.permissions.geolocation.systemAuthorizationGranted(pendingQuery: query)
            } else {
                self.updatePermissions()
            }

        case (.notDetermined, true):
            break

        case (.denied, true), (.restricted, true):
            // do not switch to `disabled` state if a website didn't ask for Location
            guard self.permissions.geolocation != nil else { break }
            self.permissions.geolocation
                .systemAuthorizationDenied(systemWide: false)

        case (_, false): // Geolocation Services disabled globally
            guard self.permissions.geolocation != nil else { break }
            self.permissions.geolocation
                .systemAuthorizationDenied(systemWide: true)

        @unknown default: break
        }
    }

}
