# Notification Service Refactor Plan

## Goal
Create a `NotificationService` that mirrors the `GeolocationService` pattern, providing:
- `authorizationStatus: UNAuthorizationStatus` property
- `authorizationStatusPublisher: AnyPublisher<UNAuthorizationStatus, Never>` for reactive updates
- Centralized notification authorization management

## Current State Analysis

### PermissionModel.swift (Current Approach)
- Uses closure-based `notificationAuthorizationProvider` injected in init
- Subscribes to `NSApplication.didBecomeActiveNotification` to check for changes
- Calls async provider when app activates: `await notificationAuthorizationProvider()`
- Updates notification permission state manually in `updateNotificationsPermission()`

### SystemPermissionManager.swift (Current Approach)
- Has basic notification authorization request in `requestAuthorization()`
- No publisher for status changes
- One-time async check, no observation

### GeolocationService.swift (Pattern to Follow)
```swift
protocol GeolocationServiceProtocol: AnyObject {
    var authorizationStatus: CLAuthorizationStatus { get }
    var authorizationStatusPublisher: AnyPublisher<CLAuthorizationStatus, Never> { get }
}

final class GeolocationService: NSObject, GeolocationServiceProtocol {
    @PublishedAfter private(set) var authorizationStatus: CLAuthorizationStatus
    var authorizationStatusPublisher: AnyPublisher<CLAuthorizationStatus, Never> {
        $authorizationStatus.eraseToAnyPublisher()
    }
    // Implements CLLocationManagerDelegate to receive status changes
}
```

## Challenge: No Native Notification Authorization Delegate

**Problem**: Unlike `CLLocationManager` which has `locationManagerDidChangeAuthorization(_:)` delegate callback, `UNUserNotificationCenter` does **not** provide delegate callbacks when authorization status changes in System Settings.

**Current iOS Pattern** (from `NotificationsAuthorizationController.swift`):
- Subscribes to `UIApplication.didBecomeActiveNotification`
- Manually checks status when app becomes active
- Compares to previous state and notifies delegate if changed

**Solution**: Implement similar pattern for macOS but with Combine publishers

## Proposed Architecture

### 1. Create NotificationService (New File)

**Location**: `macOS/DuckDuckGo/Permissions/Model/NotificationService.swift`

```swift
import Foundation
import Combine
import UserNotifications

protocol NotificationServiceProtocol: AnyObject {
    var authorizationStatus: UNAuthorizationStatus { get async }
    var authorizationStatusPublisher: AnyPublisher<UNAuthorizationStatus, Never> { get }
    
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
}

final class NotificationService: NotificationServiceProtocol {
    static let shared = NotificationService()
    
    @PublishedAfter private var currentAuthorizationStatus: UNAuthorizationStatus
    
    private var appActivationCancellable: AnyCancellable?
    
    var authorizationStatus: UNAuthorizationStatus {
        get async {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            return settings.authorizationStatus
        }
    }
    
    var authorizationStatusPublisher: AnyPublisher<UNAuthorizationStatus, Never> {
        $currentAuthorizationStatus.eraseToAnyPublisher()
    }
    
    init(appActivationPublisher: AnyPublisher<Notification, Never> = NotificationCenter.default
            .publisher(for: NSApplication.didBecomeActiveNotification)
            .eraseToAnyPublisher()) {
        
        // Initialize with current status
        let initialStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        self.currentAuthorizationStatus = initialStatus
        
        // Subscribe to app activation to poll for changes
        self.appActivationCancellable = appActivationPublisher
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.updateAuthorizationStatus()
                }
            }
    }
    
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: options)
        await updateAuthorizationStatus()
        return granted
    }
    
    private func updateAuthorizationStatus() async {
        let newStatus = await authorizationStatus
        if newStatus != currentAuthorizationStatus {
            currentAuthorizationStatus = newStatus
        }
    }
}
```

### 2. Update SystemPermissionManager

**File**: `macOS/DuckDuckGo/Permissions/Model/SystemPermissionManager.swift`

**Changes**:
- Add `notificationService: NotificationServiceProtocol` dependency
- Subscribe to `notificationService.authorizationStatusPublisher`
- Remove inline notification authorization request
- Delegate to `notificationService.requestAuthorization()`

```swift
final class SystemPermissionManager: SystemPermissionManagerProtocol {
    private let geolocationService: GeolocationServiceProtocol
    private let notificationService: NotificationServiceProtocol
    
    init(geolocationService: GeolocationServiceProtocol = GeolocationService.shared,
         notificationService: NotificationServiceProtocol = NotificationService.shared) {
        self.geolocationService = geolocationService
        self.notificationService = notificationService
    }
    
    func authorizationStateAsync(for permissionType: PermissionType) async -> SystemPermissionAuthorizationState {
        switch permissionType {
        case .notification:
            let status = await notificationService.authorizationStatus
            switch status {
            case .authorized, .provisional, .ephemeral:
                return .authorized
            case .denied:
                return .denied
            case .notDetermined:
                return .notDetermined
            @unknown default:
                return .notDetermined
            }
        // ... other cases
        }
    }
    
    func requestAuthorization(for permissionType: PermissionType, completion: @escaping (SystemPermissionAuthorizationState) -> Void) -> AnyCancellable? {
        switch permissionType {
        case .notification:
            Task {
                do {
                    let granted = try await notificationService.requestAuthorization(options: [.alert, .sound])
                    await MainActor.run {
                        completion(granted ? .authorized : .denied)
                    }
                } catch {
                    Logger.general.error("SystemPermissionManager: Notification authorization failed - \(error.localizedDescription)")
                    await MainActor.run {
                        completion(.denied)
                    }
                }
            }
            return nil
        // ... other cases
        }
    }
}
```

### 3. Update PermissionModel

**File**: `macOS/DuckDuckGo/Permissions/Model/PermissionModel.swift`

**Changes**:
- Replace `notificationAuthorizationProvider: NotificationAuthorizationProvider` with `notificationService: NotificationServiceProtocol`
- Subscribe to `notificationService.authorizationStatusPublisher` instead of app activation
- Remove `appActivationPublisher` dependency (no longer needed for notifications)
- Simplify `updateNotificationsPermission()` to use service

```swift
final class PermissionModel {
    private let permissionManager: PermissionManagerProtocol
    private let geolocationService: GeolocationServiceProtocol
    private let notificationService: NotificationServiceProtocol
    private let featureFlagger: FeatureFlagger
    
    init(webView: WKWebView? = nil,
         permissionManager: PermissionManagerProtocol,
         geolocationService: GeolocationServiceProtocol = GeolocationService.shared,
         notificationService: NotificationServiceProtocol = NotificationService.shared,
         featureFlagger: FeatureFlagger) {
        self.permissionManager = permissionManager
        self.geolocationService = geolocationService
        self.notificationService = notificationService
        self.featureFlagger = featureFlagger
        
        if let webView {
            self.webView = webView
            self.subscribe(to: webView)
            self.subscribe(to: permissionManager)
        }
        self.subscribeToNotificationService()
    }
    
    private func subscribeToNotificationService() {
        notificationService.authorizationStatusPublisher
            .sink { [weak self] status in
                Task { @MainActor [weak self] in
                    await self?.notificationAuthorizationStatusDidChange(to: status)
                }
            }
            .store(in: &cancellables)
    }
    
    private func notificationAuthorizationStatusDidChange(to status: UNAuthorizationStatus) async {
        guard featureFlagger.isFeatureOn(.newPermissionView),
              permissions.notification != nil else {
            return
        }
        
        if [.denied, .notDetermined].contains(status) {
            permissions.notification = nil
            authorizationQueries.removeAll(where: { $0.permissions == [.notification] })
        } else if permissions.notification == .active || permissions.notification == .inactive {
            permissions.notification = .active
        }
    }
}
```

## Implementation Steps

### Phase 1: Create NotificationService
1. Create `NotificationService.swift` with protocol and implementation
2. Handle async initialization challenges (initial status fetch)
3. Implement app activation observation for status changes
4. Add unit tests for NotificationService

### Phase 2: Update SystemPermissionManager
1. Add `notificationService` dependency
2. Update notification authorization methods to use service
3. Update unit tests for SystemPermissionManager

### Phase 3: Update PermissionModel
1. Replace `notificationAuthorizationProvider` with `notificationService`
2. Subscribe to authorization status publisher
3. Remove direct app activation subscription for notifications
4. Update all call sites that initialize PermissionModel
5. Update unit tests for PermissionModel

### Phase 4: Update Call Sites
1. Find all places that create `PermissionModel` instances
2. Update to pass `notificationService` instead of closure
3. Remove custom app activation publisher arguments
4. Verify tests still pass

## Async Initialization Challenge

**Problem**: Unlike `GeolocationService` which can synchronously get `locationManager.authorizationStatus`, notification authorization requires async `await UNUserNotificationCenter.current().notificationSettings()`.

**Solutions**:

### Option A: Lazy async property (Preferred)
```swift
var authorizationStatus: UNAuthorizationStatus {
    get async {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
}

private var currentAuthorizationStatus: UNAuthorizationStatus = .notDetermined

init() {
    Task {
        currentAuthorizationStatus = await authorizationStatus
    }
    // Subscribe to app activation
}
```

### Option B: Cached with initial fetch
```swift
@PublishedAfter private var currentAuthorizationStatus: UNAuthorizationStatus

init() async {
    self.currentAuthorizationStatus = await UNUserNotificationCenter.current()
        .notificationSettings().authorizationStatus
    // Subscribe to app activation
}
```
**Issue**: Makes `init()` async, which breaks call sites

### Option C: Start with .notDetermined (Simple)
```swift
@PublishedAfter private var currentAuthorizationStatus: UNAuthorizationStatus = .notDetermined

init() {
    Task {
        await updateAuthorizationStatus()
    }
    // Subscribe to app activation
}
```

**Recommendation**: Use Option A for synchronous init + Option C pattern for publisher

## Benefits

1. **Consistency**: Matches `GeolocationService` pattern
2. **Testability**: Easy to mock `NotificationServiceProtocol`
3. **Reactive**: Automatic updates via publisher
4. **Centralized**: Single source of truth for notification authorization
5. **Reusability**: Can be used by other components needing notification status
6. **Cleaner**: Removes closure injection pattern from `PermissionModel`

## Testing Strategy

### NotificationService Tests
- Test initial authorization status fetch
- Test authorization status updates on app activation
- Test request authorization flow
- Test publisher emits correct values
- Mock `UNUserNotificationCenter` for unit testing

### Integration Tests
- Test `PermissionModel` subscribes correctly to `NotificationService`
- Test `SystemPermissionManager` uses `NotificationService`
- Test authorization flow end-to-end

## Migration Risks

1. **Breaking Change**: `PermissionModel` init signature changes
   - Mitigation: Update all call sites in same PR
   
2. **Async Timing**: Initial status may not be immediately available
   - Mitigation: Start with `.notDetermined`, update quickly in Task
   
3. **Polling vs Delegate**: Notification status changes require polling
   - Mitigation: This is inherent to UNUserNotificationCenter API, same as iOS implementation

## Files to Modify

1. **New**: `macOS/DuckDuckGo/Permissions/Model/NotificationService.swift`
2. **Update**: `macOS/DuckDuckGo/Permissions/Model/SystemPermissionManager.swift`
3. **Update**: `macOS/DuckDuckGo/Permissions/Model/PermissionModel.swift`
4. **Update**: All call sites creating `PermissionModel` (TBD - need to find these)
5. **New**: `macOS/UnitTests/Permissions/NotificationServiceTests.swift`
6. **Update**: `macOS/UnitTests/Permissions/SystemPermissionManagerTests.swift`
7. **Update**: `macOS/UnitTests/Permissions/PermissionModelTests.swift`

## Open Questions

1. Should `NotificationService` be a singleton (`.shared`) like `GeolocationService`?
   - **Recommendation**: Yes, for consistency

2. Should we handle notification settings changes beyond authorization (e.g., alert style)?
   - **Recommendation**: No, just authorization status for now

3. Should `NotificationService` live in shared packages for iOS reuse?
   - **Recommendation**: Start in macOS, consider sharing if iOS needs it later

4. Do we need to handle ephemeral/provisional authorization states specially?
   - **Recommendation**: Treat as authorized, matching current behavior

## Timeline Estimate

- **Phase 1** (NotificationService): 2-3 hours
- **Phase 2** (SystemPermissionManager): 1 hour  
- **Phase 3** (PermissionModel): 2-3 hours
- **Phase 4** (Call sites + integration): 2-3 hours
- **Testing + Polish**: 2-3 hours

**Total**: 1-2 days of focused work

