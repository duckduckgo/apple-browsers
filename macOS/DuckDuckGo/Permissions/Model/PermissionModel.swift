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
import Common
import ConcurrencyExtensions
import CoreLocation
import DDGNavigation
import FeatureFlags_macOS
import Foundation
import os.log
import PrivacyConfig
import UserNotifications
import WebKit

typealias NotificationAuthorizationProvider = @Sendable () async -> UNAuthorizationStatus

final class PermissionModel {

    @PublishedAfter private(set) var permissions = Permissions()
    @PublishedAfter private(set) var authorizationQuery: PermissionAuthorizationQuery?
    /// Set to true when permissions are changed in the Permission Center and a reload is needed
    @PublishedAfter private(set) var permissionsNeedReload = false

    /// Fires when permission blocked due to system being disabled - view layer shows info popover
    let permissionBlockedBySystem = PassthroughSubject<(domain: String, permissionType: PermissionType), Never>()

    let popupDecisionRemoved = PassthroughSubject<Void, Never>()

    private(set) var authorizationQueries = [PermissionAuthorizationQuery]() {
        didSet {
            authorizationQuery = authorizationQueries.last
        }
    }

    /// The new prompt handles system-disabled access itself, so a pending request still needs to be presented.
    var authorizationQueryForPresentation: PermissionAuthorizationQuery? {
        if featureFlagger.isFeatureOn(.websitePermissionsPrompts) {
            guard let authorizationQuery, !authorizationQuery.isComplete else { return nil }
            return authorizationQuery
        }
        return permissions.values.compactMap { state -> PermissionAuthorizationQuery? in
            guard case .requested(let query) = state else { return nil }
            return query
        }.first
    }

    private let permissionManager: PermissionManagerProtocol
    private let geolocationService: GeolocationServiceProtocol
    private let systemPermissionManager: SystemPermissionManagerProtocol
    private let featureFlagger: FeatureFlagger

    private var temporarilyAllowedExternalSchemes: [String: Set<PermissionType>] = [:]

    /// Holds the set of permissions the user manually removed (to avoid adding them back via updatePermissions)
    private var removedPermissions = Set<PermissionType>()

    private var deniedByCategoryDefault = Set<PermissionType>()

    weak var webView: WKWebView? {
        didSet {
            guard let webView = webView else { return }
            assert(oldValue == nil)
            self.subscribe(to: webView)
            self.subscribe(to: permissionManager)
        }
    }
    private var cancellables = Set<AnyCancellable>()

    /// Returns the domain permissions are saved under for the current webView URL.
    private var currentDomain: String? {
        guard let url = webView?.url else { return nil }
        return url.isFileURL ? permissionDomain(for: url) : url.host
    }

    /// With the new prompts, local files have their own permission key, apart from `localhost`.
    /// Without them, local files keep their old keys: `localhost` for a page URL, an empty host for a frame origin.
    private var savesLocalFilePermissionsSeparately: Bool {
        featureFlagger.isFeatureOn(.websitePermissionsPrompts)
    }

    /// The domain website permissions are saved under for a page.
    func permissionDomain(for url: URL) -> String {
        guard url.isFileURL else { return url.host ?? "" }
        return savesLocalFilePermissionsSeparately ? .localFilePermissionDomain : .localhost
    }

    /// The domain website permissions are saved under for a frame's origin.
    func permissionDomain(for origin: SecurityOrigin) -> String {
        guard origin.protocol == "file", savesLocalFilePermissionsSeparately else { return origin.host }
        return .localFilePermissionDomain
    }

    /// Creates the model for one tab; pass `webView` now or assign it later to start tracking its permissions.
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

    /// Follows the web view's camera, microphone and location usage to keep `permissions` up to date.
    private func subscribe(to webView: WKWebView) {
        webView.publisher(for: \.cameraCaptureState).sink { [weak self] _ in
            self?.updatePermissions()
        }.store(in: &cancellables)
        webView.publisher(for: \.microphoneCaptureState).sink { [weak self] _ in
            self?.updatePermissions()
        }.store(in: &cancellables)

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

    /// Follows saved decision changes (e.g. made in Settings) to apply them to the current page.
    private func subscribe(to permissionManager: PermissionManagerProtocol) {
        permissionManager.permissionPublisher.sink { [weak self, weak permissionManager] value in
            guard let permissionManager else { return }

            self?.permissionManager(permissionManager,
                                    didChangePermission: value.permissionType,
                                    forDomain: value.domain,
                                    change: value.change)
        }.store(in: &cancellables)
    }

    /// Forgets everything tied to the current page: active permissions, pending prompts and per-page decisions.
    private func resetPermissions() {
        webView?.configuration.processPool.geolocationProvider?.reset()
        webView?.revokePermissions([.camera, .microphone])
        for permission in permissions.keys {
            // await permission deactivation and transition to .none
            permissions[permission].willReload()
        }
        authorizationQueries = []
        temporarilyAllowedExternalSchemes.removeAll()
        removedPermissions.removeAll()
        deniedByCategoryDefault.removeAll()
        clearPermissionsNeedReload()
    }

    /// Syncs camera, microphone and location states with what the web view actually uses right now.
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

                    // Keep geolocation as active once it's been granted/used
                    // (.active or .inactive means it was granted or actively used)
                    if currentState == .none,
                       permissions.geolocation == .active || permissions.geolocation == .inactive {
                        permissions.geolocation = .active
                    } else {
                        permissions.geolocation.update(with: currentState)
                    }
                }
            case .notification, .popups, .externalScheme, .autoplayPolicy:
                continue
            }
        }
    }

    /// Legacy Allow / Deny prompt rule: a notification decision is saved unless the website is explicitly set to "Ask".
    private func persistsWhen(permission: PermissionType, domain: String) -> Bool {
        switch permission {
        case .notification:
            return !permissionManager.hasPermissionPersisted(forDomain: domain, permissionType: permission)
                || permissionManager.permission(forDomain: domain, permissionType: permission) != .ask
        default:
            return false
        }
    }

    /// Whether the user's answer to a prompt should be saved for the website.
    private func shouldPersistDecision(remember: Bool?, for permission: PermissionType, domain: String) -> Bool {
        switch remember {
        case .some(let remember):
            // Explicit choice: `true` for Always allow / Never allow (and the Allow / Deny prompt's
            // Duck.ai microphone exception), `false` for Allow this visit.
            return remember
        case .none:
            // No explicit choice (the Allow / Deny prompt): keep the legacy rule,
            // which saves a site's first notification decision.
            return persistsWhen(permission: permission, domain: domain)
        }
    }

    /// Whether "Allow once" for an external app should be kept until the next navigation.
    private func shouldStoreTemporaryGrant(granted: Bool, remember: Bool?, for permission: PermissionType) -> Bool {
        granted && remember == false && permission.isExternalScheme && featureFlagger.isFeatureOn(.websitePermissionsPrompts)
    }

    /// Asks the user: adds a prompt to `authorizationQueries` and applies (and maybe saves) the answer when it comes.
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

                let completedQuery = self.authorizationQueries.remove(at: idx)

                if case .failure = result {
                    self.clearDismissedQuery(completedQuery)
                }

                if case .success( (let granted, let remember) ) = result {
                    for permission in permissions {
                        if self.shouldStoreTemporaryGrant(granted: granted, remember: remember, for: permission) {
                            self.temporarilyAllowedExternalSchemes[domain.droppingWwwPrefix(), default: []].insert(permission)
                        }
                        if self.shouldPersistDecision(remember: remember, for: permission, domain: domain) {
                            self.permissionManager.setPermission(granted ? .allow : .deny, forDomain: domain, permissionType: permission)
                        } else if remember == nil {
                            // The legacy Allow / Deny prompt stores .ask for permission center visibility.
                            // Allow this visit (`remember == false`) is temporary and is never stored.
                            self.permissionManager.setPermission(.ask, forDomain: domain, permissionType: permission)
                        }
                    }
                }
            } // else: query has been removed, the decision is being handled on the query deallocation

            decisionHandler(isGranted)
        }
        // "unowned" query reference to be able to use the pointer when the callback is called on query deinit
        queryPtr = Unmanaged.passUnretained(query).toOpaque()

        // Set state to .requested so the authorization popover can be shown
        permissions.forEach { self.permissions[$0].authorizationQueried(query, updateQueryIfAlreadyRequested: $0 == .popups) }
        query.isSystemPermissionDisabled = isSystemPermissionDisabled
        authorizationQueries.append(query)
    }

    /// Drops the `.requested` state of a prompt the user dismissed, so the address bar stops showing it.
    private func clearDismissedQuery(_ query: PermissionAuthorizationQuery) {
        // Only the new prompt marks explicit dismissals. Legacy cancellation keeps its existing state.
        guard query.wasDismissed, featureFlagger.isFeatureOn(.websitePermissionsPrompts) else { return }
        for permission in query.permissions {
            if case .requested(let pendingQuery) = permissions[permission], pendingQuery === query {
                permissions[permission] = nil
            }
        }
    }

    /// Applies a saved decision change for the current website: revokes, resets or answers pending prompts.
    private func permissionManager(_: PermissionManagerProtocol,
                                   didChangePermission permissionType: PermissionType,
                                   forDomain domain: String,
                                   change: PermissionChange) {
        temporarilyAllowedExternalSchemes[domain.droppingWwwPrefix()]?.remove(permissionType)
        guard currentDomain?.droppingWwwPrefix() == domain else { return }

        switch change {
        case .removed:
            removePermissionFromCurrentPage(permissionType)
            if permissionType == .popups {
                popupDecisionRemoved.send()
            }
        case .decisionChanged(let decision):
            // Allow updatePermissions() to track the permission again when access is restored.
            if decision == .allow {
                removedPermissions.remove(permissionType)
            }

            switch (decision, self.permissions[permissionType]) {
            case (.ask, .denied):
                self.permissions[permissionType] = nil
            case (.deny, .some):
                self.revoke(permissionType)
                fallthrough
            case (.allow, .requested):
                while let query = self.authorizationQueries.first(where: { $0.permissions == [permissionType] }) {
                    query.handleDecision(grant: decision == .allow, remember: true)
                }
            default: break
            }
        }
    }

    // MARK: Pausing/Revoking

    /// Pauses or resumes camera, microphone or location use without revoking the permission.
    func set(_ permissions: [PermissionType], muted: Bool) {
        webView?.setPermissions(permissions, muted: muted)
    }

    /// Grants a pending prompt, e.g. from the address bar button.
    func allow(_ query: PermissionAuthorizationQuery) {
        guard self.authorizationQueries.contains(where: { $0 === query }) else {
            assertionFailure("unexpected Permission state")
            return
        }
        query.handleDecision(grant: true)
    }

    /// Stops a granted permission on the current page and turns a saved "Always Allow" back into "Ask".
    func revoke(_ permission: PermissionType) {
        clearTemporaryExternalSchemeGrant(for: permission)
        if let domain = currentDomain,
           case .allow = permissionManager.permission(forDomain: domain, permissionType: permission) {
            permissionManager.setPermission(.ask, forDomain: domain, permissionType: permission)
        }
        switch permission {
        case .camera, .microphone, .geolocation:
            self.permissions[permission].revoke() // await deactivation
            webView?.revokePermissions([permission])

        case .popups, .notification, .externalScheme, .autoplayPolicy:
            self.permissions[permission].denied()
        }
    }

    /// Removes a permission completely (revokes and removes from tracking)
    func remove(_ permission: PermissionType) {
        removePermissionFromCurrentPage(permission)

        // Remove from persisted storage
        if let domain = currentDomain {
            permissionManager.removePermission(forDomain: domain, permissionType: permission)
        } else {
            assertionFailure("webView URL should not be nil when removing a permission")
        }
    }

    /// Revokes the permission on the current page and stops tracking it until access is granted again.
    private func removePermissionFromCurrentPage(_ permission: PermissionType) {
        clearTemporaryExternalSchemeGrant(for: permission)
        // Track as explicitly removed to prevent re-adding via updatePermissions()
        guard removedPermissions.insert(permission).inserted else { return }

        // First revoke the permission
        switch permission {
        case .camera, .microphone, .geolocation:
            webView?.revokePermissions([permission])
        case .popups, .notification, .externalScheme, .autoplayPolicy:
            break
        }

        // Remove from dictionary (will trigger @Published update)
        permissions[permission] = nil
    }

    /// Forgets "Allow once" for an external app on all websites.
    private func clearTemporaryExternalSchemeGrant(for permission: PermissionType) {
        for domain in temporarilyAllowedExternalSchemes.keys {
            temporarilyAllowedExternalSchemes[domain]?.remove(permission)
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

    /// WebKit before Safari 26 (macOS 12–13, and 14–15 without Safari 26): called before WebKit validates system
    /// media permissions, without telling which media type is requested.
    @available(macOS, deprecated: 26.0, message: "Safari 26's WebKit calls queryMediaPermission(_:) instead. Remove when macOS 26 is the minimum.")
    @MainActor
    func checkUserMediaPermission(for url: URL?, mainFrameURL: URL?, decisionHandler: @escaping (String, Bool) -> Void) {
        // The requested media type is only known from WebKit's following status checks, so cover both:
        // the request drops the token WebKit didn't use (see `permissions(_:requestedForDomain:)`).
        if featureFlagger.isFeatureOn(.websitePermissionsPrompts) {
            // Same as `queryMediaPermission(_:)`: reach our website prompt before macOS rejects or asks
            AVCaptureDevice.authorizeNextStatusCheck(for: [.audio, .video], owner: ObjectIdentifier(self))
        } else {
            // If media capture is denied in the System Preferences, reflect it in the current permissions:
            // otherwise WebView won't call any other delegate methods if System Permission is denied
            AVCaptureDevice.observeNextStatusCheck(for: [.audio, .video], owner: ObjectIdentifier(self)) { [weak self] mediaType, authorizationStatus in
                guard authorizationStatus == .denied || authorizationStatus == .restricted else { return }
                let permission: PermissionType = mediaType == .audio ? .microphone : .camera
                self?.permissions[permission].systemAuthorizationDenied(systemWide: false)
            }
        }
        decisionHandler(/*salt - seems not used anywhere:*/ "", /*includeSensitiveMediaDeviceDetails:*/ false)
    }

    /// Safari 26+ WebKit: called with "camera" and "microphone" before WebKit validates system media permissions.
    /// Authorizes WebKit's next system status check so it reaches our website prompt before requesting or rejecting
    /// system access, otherwise WebView won't call any other delegate methods if System Permission is denied.
    /// The prompt checks the real macOS status and holds its decision until access is granted.
    @MainActor
    func queryMediaPermission(_ name: String) {
        guard featureFlagger.isFeatureOn(.websitePermissionsPrompts) else { return }
        switch name {
        case "camera":
            AVCaptureDevice.authorizeNextStatusCheck(for: [.video], owner: ObjectIdentifier(self))
        case "microphone":
            AVCaptureDevice.authorizeNextStatusCheck(for: [.audio], owner: ObjectIdentifier(self))
        default:
            break
        }
    }

    /// Whether popups are blocked only by the "Block" category default, with nothing saved for the website.
    func isPopupBlockedByDefault(forDomain domain: String) -> Bool {
        isBlockedByCategoryDefault(.popups, forDomain: domain)
    }

    /// Whether the permission is denied only by the "Block" category default, with nothing saved for the website.
    private func isBlockedByCategoryDefault(_ permission: PermissionType, forDomain domain: String) -> Bool {
        !permissionManager.hasPermissionPersisted(forDomain: domain, permissionType: permission)
            && permissionManager.permission(forDomain: domain, permissionType: permission) == .deny
    }

    /// Whether a stored deny applies: the "Block" default always does, a saved "Never Allow" only for types that keep denials.
    private func shouldApplyDenial(of permission: PermissionType, isPersistedForDomain: Bool) -> Bool {
        let comesFromCategoryDefault = !isPersistedForDomain
        return permission.canPersistDeniedDecision || comesFromCategoryDefault
    }

    /// Decides a permission request from what we already know, without asking the user.
    ///
    /// - Returns: `true` to grant right away, `false` to deny right away, `nil` when the user has to be asked.
    ///
    /// Each requested permission is resolved to allow / deny / ask, first match wins:
    /// 1. The website's saved decision ("Always Allow" / "Never Allow" in the prompt or Settings).
    ///    `permissionManager` falls back to the category default (Settings › "Ask" / "Block" for all websites)
    ///    when nothing is saved for this website. A "Block" default denies every type; a saved "Never Allow"
    ///    only denies types with `canPersistDeniedDecision` (not popups).
    /// 2. "Allow once" for an external app, kept until the next navigation (website prompts only).
    /// 3. What happened on this page: a permission denied earlier stays denied until the next navigation,
    ///    so the user isn't asked again. A denial that only came from the "Block" default is asked again,
    ///    so changing the default takes effect without reloading.
    /// 4. Otherwise ask.
    ///
    /// Then for the whole request: any deny denies it all, all allow grants it, anything else asks the user.
    /// An allow still asks when macOS access isn't granted (see `isSystemPermissionDisabled`), and with website prompts
    /// also when macOS hasn't asked yet: the website prompt has to come before the macOS one, and shows its
    /// System Settings step for denied access.
    private func shouldGrantPermission(for permissions: [PermissionType], requestedForDomain domain: String) -> Bool? {
        var shouldAsk = false
        for permission in permissions {
            var grant: PersistedPermissionDecision
            let stored = permissionManager.permission(forDomain: domain, permissionType: permission)
            let isPersistedForDomain = permissionManager.hasPermissionPersisted(forDomain: domain, permissionType: permission)
            if case .allow = stored, permission.canPersistGrantedDecision {
                // 1. "Always Allow" saved for the website
                grant = .allow
            } else if case .deny = stored, shouldApplyDenial(of: permission, isPersistedForDomain: isPersistedForDomain) {
                // 1. "Never Allow" saved for the website, or the "Block" category default
                grant = .deny
            } else if featureFlagger.isFeatureOn(.websitePermissionsPrompts),
                      temporarilyAllowedExternalSchemes[domain.droppingWwwPrefix()]?.contains(permission) == true {
                // 2. external app allowed once on this page
                grant = .allow
            } else if let state = self.permissions[permission] {
                switch state {
                // 3. already denied on this page: deny again, unless only the "Block" default denied it
                case .denied, .revoking:
                    grant = deniedByCategoryDefault.contains(permission) ? .ask : .deny
                // 3. requested, granted or used on this page: a new request still needs the user's answer
                case .disabled, .requested, .active, .inactive, .paused, .reloading:
                    grant = .ask
                }
            } else {
                // 4. nothing known
                grant = .ask
            }

            switch grant {
            case .deny:
                // One denied permission denies the whole request, the macOS status doesn't matter
                return false
            case .allow:
                // Allowed for the website, but macOS has to allow it too
                if isSystemPermissionDisabled(for: permission) {
                    shouldAsk = true
                } else if featureFlagger.isFeatureOn(.websitePermissionsPrompts),
                          permission.requiresSystemPermission,
                          systemPermissionManager.cachedAuthorizationState(for: permission) == .notDetermined {
                    // A macOS permission reset must return to the website choices before requesting system access.
                    shouldAsk = true
                }
            case .ask:
                // Keep checking the other permissions: a denial among them wins over asking
                shouldAsk = true
            }
        }
        return shouldAsk ? nil : true
    }

    /// Checks if system-level permission is disabled for the given permission type (uses cached state for sync access)
    private func isSystemPermissionDisabled(for permissionType: PermissionType) -> Bool {
        guard permissionType.requiresSystemPermission else { return false }
        if permissionType == .camera || permissionType == .microphone,
           !featureFlagger.isFeatureOn(.websitePermissionsPrompts) {
            return false
        }

        let authState = systemPermissionManager.cachedAuthorizationState(for: permissionType)
        return authState == .denied || authState == .restricted || authState == .systemDisabled
    }

    /// Entry point for every website permission request: camera, microphone, location, notifications, popups,
    /// external apps and autoplay. Called from the WebKit UI delegate, tab extensions and user scripts.
    ///
    /// Normal flow:
    /// 1. `shouldGrantPermission` decides from saved decisions and this page's history, without asking the user.
    /// 2. A grant or a deny calls `decisionHandler` right away (synchronously). A deny also marks the permissions
    ///    `.denied` for this page, so the address bar shows them blocked and repeated requests are denied too.
    /// 3. Otherwise the user is asked: a `PermissionAuthorizationQuery` is appended to `authorizationQueries`,
    ///    the permissions become `.requested` and the address bar shows the prompt. `decisionHandler` is called
    ///    when the user answers, with `false` if the prompt is dismissed or the tab navigates away first.
    ///
    /// When the website is allowed but macOS access is denied in System Settings:
    /// - with website prompts, the prompt opens on its System Settings step and grants the request once macOS does;
    /// - without them, the request is denied and `permissionBlockedBySystem` shows an informational popover.
    ///
    /// All permissions of one request get one decision, e.g. camera + microphone for a video call.
    func permissions(_ permissions: [PermissionType], requestedForDomain domain: String, url: URL? = nil, decisionHandler: @escaping (Bool) -> Void) {
        guard !permissions.isEmpty else {
            assertionFailure("Unexpected permissions/domain")
            decisionHandler(false)
            return
        }
        if permissions.contains(.camera) || permissions.contains(.microphone) {
            // WebKit has already checked the macOS status (see `queryMediaPermission(_:)`): drop the unused
            // tokens so they don't affect the app's own reads. Tokens are process-wide, so only drop this tab's.
            MainActor.assumeMainThread {
                AVCaptureDevice.resetAuthorizationStatusOverrides(owner: ObjectIdentifier(self))
            }
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
            // Allowed for the website, but denied in macOS System Settings?
            let isSystemDisabled: Bool = {
                permissions.contains(where: isSystemPermissionDisabled)
                    && permissions.allSatisfy { self.permissionManager.permission(forDomain: domain, permissionType: $0) == .allow }
            }()

            if isSystemDisabled, featureFlagger.isFeatureOn(.websitePermissionsPrompts) {
                // The prompt opens on its System Settings step and grants the request once macOS does
                self.queryAuthorization(for: permissions, domain: domain, url: url,
                                        isSystemPermissionDisabled: true,
                                        decisionHandler: wrappedDecisionHandler)
            } else if isSystemDisabled {
                // Deny - system permission is disabled, can't deliver anyway
                wrappedDecisionHandler(false)
                // Fire event for view layer to show informational popover
                permissionBlockedBySystem.send((domain: domain, permissionType: permissions.first!))
            } else {
                // Ask the user; the answer replaces a denial that came from the "Block" default
                deniedByCategoryDefault.subtract(permissions)
                self.queryAuthorization(for: permissions, domain: domain, url: url,
                                        isSystemPermissionDisabled: false,
                                        decisionHandler: wrappedDecisionHandler)
            }
        case .some(true):
            wrappedDecisionHandler(true)
        case .some(false):
            wrappedDecisionHandler(false)
            // Remember denials coming only from the "Block" default, so they're asked again once it changes
            let isDeniedByCategoryDefault = permissions.contains { isBlockedByCategoryDefault($0, forDomain: domain) }
            for permission in permissions {
                let wasDeniedEarlierOnPage = self.permissions[permission] == .denied
                if isDeniedByCategoryDefault, !wasDeniedEarlierOnPage {
                    deniedByCategoryDefault.insert(permission)
                }
                self.permissions[permission].denied()
            }
        }
    }

    /// Same as the `Bool` version, for WebKit delegate methods that take a `WKPermissionDecision`.
    func permissions(_ permissions: [PermissionType], requestedForDomain domain: String, url: URL? = nil, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        self.permissions(permissions, requestedForDomain: domain, url: url) { isGranted in
            decisionHandler(isGranted ? .grant : .deny)
        }
    }

    /// Updates the state of permissions that have no ongoing usage to track (popups, external apps) once granted.
    private func permissionGranted(for permission: PermissionType) {
        // handle special permission granted for permission without `active` (used) state
        switch permission {
        case .externalScheme:
            self.permissions[permission].externalSchemeOpened()
        case .popups:
            self.permissions[permission].popupOpened(nextQuery: authorizationQueries.first(where: { $0.permissions.contains(.popups) }))
        case .camera, .microphone, .geolocation, .notification, .autoplayPolicy:
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

    /// Called by WebKit when camera or microphone capture starts, stops or is muted.
    func mediaCaptureStateDidChange() {
        updatePermissions()
    }

    /// Called when the tab navigates: permissions granted or denied on the previous page no longer apply.
    func tabDidStartNavigation() {
        resetPermissions()
    }

    /// Reflects macOS Location Services changes: shows a waiting prompt once allowed, the disabled state once denied.
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

extension String {
    /// Website permissions from every local file are saved under this key, apart from `localhost`,
    /// so a local development server keeps its own permissions. It can't collide with a host name.
    static let localFilePermissionDomain = "file://"

    /// The name shown for a permission domain in prompts and Settings.
    var permissionDisplayName: String {
        self == .localFilePermissionDomain ? UserText.websitePermissionsLocalFile : self
    }
}
