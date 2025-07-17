---
title: "macOS System Integration Patterns"
description: "macOS system integration patterns including services, extensions, background agents, login items, and workspace integration"
keywords: ["macOS", "system integration", "background agents", "system extensions", "login items", "notifications", "app groups", "workspace"]
alwaysApply: false
---

# macOS System Integration Patterns

## Background Agents and Services
Use proper service management for background agents:

```swift
// ✅ CORRECT - Background service management
final class BackgroundServiceManager {
    private let agentIdentifier = "com.duckduckgo.agent"
    private let extensionIdentifier = "com.duckduckgo.extension"
    
    func registerBackgroundAgent() throws {
        let service = SMAppService.agent(plistName: "BackgroundAgent.plist")
        
        do {
            try service.register()
            print("Background agent registered successfully")
        } catch {
            print("Failed to register background agent: \(error)")
            throw error
        }
    }
    
    func unregisterBackgroundAgent() throws {
        let service = SMAppService.agent(plistName: "BackgroundAgent.plist")
        
        do {
            try service.unregister()
            print("Background agent unregistered successfully")
        } catch {
            print("Failed to unregister background agent: \(error)")
            throw error
        }
    }
    
    func checkServiceStatus() -> SMAppService.Status {
        let service = SMAppService.agent(plistName: "BackgroundAgent.plist")
        return service.status
    }
}

// ❌ INCORRECT - Direct background processing in main app
final class FeatureManager {
    func startBackgroundWork() {
        // Don't run continuous background work in main app
        DispatchQueue.global().async {
            while true {
                // This will drain battery and violate sandboxing
                self.performWork()
                Thread.sleep(forTimeInterval: 60)
            }
        }
    }
}
```

## System Extensions
Use proper system extension lifecycle management:

```swift
// ✅ CORRECT - System extension management
import SystemExtensions

final class SystemExtensionManager: NSObject {
    private let extensionIdentifier = "com.duckduckgo.network-extension"
    
    func installExtension() {
        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: extensionIdentifier,
            queue: .main
        )
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }
    
    func uninstallExtension() {
        let request = OSSystemExtensionRequest.deactivationRequest(
            forExtensionWithIdentifier: extensionIdentifier,
            queue: .main
        )
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }
    
    func checkExtensionStatus() async -> OSSystemExtensionRequest.Result? {
        // Check if extension is already installed
        return await withCheckedContinuation { continuation in
            let request = OSSystemExtensionRequest.propertiesRequest(
                forExtensionWithIdentifier: extensionIdentifier,
                queue: .main
            )
            
            // Handle the properties request to determine status
            // Implementation details...
            continuation.resume(returning: nil)
        }
    }
}

// MARK: - OSSystemExtensionRequestDelegate
extension SystemExtensionManager: OSSystemExtensionRequestDelegate {
    func request(
        _ request: OSSystemExtensionRequest,
        actionForReplacingExtension existing: OSSystemExtensionProperties,
        withExtension extension: OSSystemExtensionProperties
    ) -> OSSystemExtensionRequest.ReplacementAction {
        return .replace
    }
    
    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        print("System extension requires user approval")
        // Show UI to guide user through approval process
        showUserApprovalGuidance()
    }
    
    func request(
        _ request: OSSystemExtensionRequest,
        didFinishWithResult result: OSSystemExtensionRequest.Result
    ) {
        switch result {
        case .completed:
            print("System extension request completed successfully")
            handleExtensionActivated()
        case .willCompleteAfterReboot:
            print("System extension will be activated after reboot")
            showRebootRequiredMessage()
        @unknown default:
            print("Unknown system extension result: \(result)")
        }
    }
    
    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        print("System extension request failed: \(error)")
        handleExtensionError(error)
    }
    
    private func showUserApprovalGuidance() {
        // Show UI to guide user through System Preferences
    }
    
    private func handleExtensionActivated() {
        // Update UI to reflect extension is active
    }
    
    private func showRebootRequiredMessage() {
        // Show UI indicating reboot is required
    }
    
    private func handleExtensionError(_ error: Error) {
        // Handle extension installation errors
    }
}
```

## Login Items Management
Use the modern SMAppService API for login items:

```swift
// ✅ CORRECT - Modern login items API
import ServiceManagement

final class LoginItemsManager {
    func enableLoginItem() throws {
        do {
            try SMAppService.mainApp.register()
            print("Login item enabled successfully")
        } catch {
            print("Failed to enable login item: \(error)")
            throw LoginItemError.registrationFailed(error)
        }
    }
    
    func disableLoginItem() throws {
        do {
            try SMAppService.mainApp.unregister()
            print("Login item disabled successfully")
        } catch {
            print("Failed to disable login item: \(error)")
            throw LoginItemError.unregistrationFailed(error)
        }
    }
    
    var isLoginItemEnabled: Bool {
        return SMAppService.mainApp.status == .enabled
    }
    
    var loginItemStatus: SMAppService.Status {
        return SMAppService.mainApp.status
    }
}

enum LoginItemError: LocalizedError {
    case registrationFailed(Error)
    case unregistrationFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .registrationFailed(let error):
            return "Failed to register login item: \(error.localizedDescription)"
        case .unregistrationFailed(let error):
            return "Failed to unregister login item: \(error.localizedDescription)"
        }
    }
}

// ❌ INCORRECT - Deprecated APIs
final class OldLoginItemsManager {
    func enableLoginItem() {
        // Don't use deprecated LSSharedFileList APIs
        let loginItems = LSSharedFileListCreate(nil, kLSSharedFileListSessionLoginItems, nil)
        // ... deprecated implementation
    }
}
```

## Workspace Integration
Integrate properly with macOS workspace:

```swift
// ✅ CORRECT - Workspace integration
final class WorkspaceIntegration {
    func openFileInFinder(at url: URL) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
    }
    
    func revealInFinder(fileAt url: URL) {
        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
    }
    
    func openWithDefaultApplication(url: URL) {
        NSWorkspace.shared.open(url)
    }
    
    func openWithApplication(url: URL, applicationURL: URL) {
        NSWorkspace.shared.open([url], withApplicationAt: applicationURL, configuration: NSWorkspace.OpenConfiguration())
    }
    
    func getDefaultApplication(for url: URL) -> URL? {
        return NSWorkspace.shared.urlForApplication(toOpen: url)
    }
}
```

## Dock Integration
Handle dock interactions properly:

```swift
// ✅ CORRECT - Dock integration
final class DockIntegration {
    func setBadgeCount(_ count: Int) {
        NSApp.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
    }
    
    func clearBadge() {
        NSApp.dockTile.badgeLabel = nil
    }
    
    func setDockMenu(_ menu: NSMenu) {
        NSApp.dockTile.contentView = nil
        NSApp.dockTile.showsApplicationBadge = true
        // Custom dock menu would be set through app delegate
    }
}

// In AppDelegate
extension AppDelegate: NSApplicationDelegate {
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let dockMenu = NSMenu()
        
        dockMenu.addItem(NSMenuItem(
            title: "New Window",
            action: #selector(newWindow),
            keyEquivalent: ""
        ))
        
        dockMenu.addItem(NSMenuItem(
            title: "New Private Window",
            action: #selector(newPrivateWindow),
            keyEquivalent: ""
        ))
        
        return dockMenu
    }
    
    @objc func newWindow() {
        WindowsManager.openNewWindow()
    }
    
    @objc func newPrivateWindow() {
        WindowsManager.openNewWindow(burnerMode: .burner)
    }
}
```

## Notification Center Integration
Handle notifications properly:

```swift
// ✅ CORRECT - User notification handling
import UserNotifications

final class NotificationManager: NSObject {
    func requestNotificationPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            return granted
        } catch {
            print("Failed to request notification permission: \(error)")
            return false
        }
    }
    
    func scheduleNotification(title: String, body: String, identifier: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )
        
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("Failed to schedule notification: \(error)")
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate
extension NotificationManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Handle notification tap
        handleNotificationResponse(response)
        completionHandler()
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound])
    }
    
    private func handleNotificationResponse(_ response: UNNotificationResponse) {
        // Handle different notification actions
        switch response.actionIdentifier {
        case UNNotificationDefaultActionIdentifier:
            // User tapped the notification
            break
        case UNNotificationDismissActionIdentifier:
            // User dismissed the notification
            break
        default:
            break
        }
    }
}
```

## App Group UserDefaults
Use app group UserDefaults for settings shared with system extensions:

```swift
// ✅ CORRECT - App group UserDefaults
extension AppUserDefaults {
    private static let appGroupUserDefaults = UserDefaults(suiteName: "group.com.duckduckgo.app")
    
    var networkProtectionEnabled: Bool {
        get { 
            appGroupUserDefaults?.bool(forKey: "network_protection_enabled") ?? false 
        }
        set { 
            appGroupUserDefaults?.set(newValue, forKey: "network_protection_enabled")
            // Notify system extension of change
            notifySystemExtension(of: .networkProtectionToggled(newValue))
        }
    }
    
    var vpnServerLocation: String? {
        get { 
            appGroupUserDefaults?.string(forKey: "vpn_server_location") 
        }
        set { 
            appGroupUserDefaults?.set(newValue, forKey: "vpn_server_location")
        }
    }
    
    private func notifySystemExtension(of change: SystemExtensionNotification) {
        // Send notification to system extension via app group communication
        let notificationName = "com.duckduckgo.settings.changed"
        DistributedNotificationCenter.default().post(
            name: Notification.Name(notificationName),
            object: change.rawValue
        )
    }
}

enum SystemExtensionNotification: String {
    case networkProtectionToggled = "network_protection_toggled"
    case vpnServerChanged = "vpn_server_changed"
}
```

See `macos-window-management.md` for window management patterns and `macos-preferences.md` for preferences UI patterns.