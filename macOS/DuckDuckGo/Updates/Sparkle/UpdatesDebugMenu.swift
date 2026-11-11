//
//  UpdatesDebugMenu.swift
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

import AppKitExtensions

import AIChat
import AppKit
import AppUpdaterShared
import Common
import FoundationExtensions
import CryptoKit
import os.log
import Persistence
import PrivacyConfig
import PixelKit

@MainActor
final class UpdatesDebugMenu: NSMenu {
    private let settings: any ThrowingKeyedStoring<UpdateControllerSettings>
    private let internalUserDecider: InternalUserDecider
    private let debugSettings = UpdatesDebugSettings()
    private let forceUpdateAvailableMenuItem = NSMenuItem(title: "Force Update Available", action: #selector(toggleForceUpdateAvailable))
    #if DEBUG
    private let metadataServerMenuItem = NSMenuItem(title: "")
    #endif

    init(keyValueStore: ThrowingKeyValueStoring, internalUserDecider: InternalUserDecider) {
        self.settings = keyValueStore.throwingKeyedStoring()
        self.internalUserDecider = internalUserDecider
        super.init(title: "")

        buildItems {
            let buildType = StandardApplicationBuildType()
            if buildType.isSparkleBuild && (buildType.isDebugBuild || buildType.isReviewBuild || internalUserDecider.isInternalUser) {
                NSMenuItem(title: "Set custom feed URL…", action: #selector(setCustomFeedURL))
                    .targetting(self)
                NSMenuItem(title: "Reset feed URL to default", action: #selector(resetFeedURLToDefault))
                    .targetting(self)
                NSMenuItem(title: "Set up Sparkle testing environment…", action: #selector(setupSparkleTestingEnvironment))
                    .targetting(self)
                NSMenuItem.separator()
            }
            if buildType.isSparkleBuild {
                NSMenuItem(title: "Simulate New User", action: #selector(simulateNewUser))
                    .targetting(self)
                NSMenuItem(title: "Simulate Legacy User", action: #selector(simulateLegacyUser))
                    .targetting(self)
                NSMenuItem.separator()
                NSMenuItem(title: "Show Browser Updated Popover", action: #selector(showBrowserUpdatedPopover))
                    .targetting(self)
                NSMenuItem(title: "Show Critical Update Popover", action: #selector(showCriticalUpdatePopover))
                    .targetting(self)
                NSMenuItem.separator()
                NSMenuItem(title: "Test Update Pixels") {
                    NSMenuItem(title: "Success (Expected)", action: #selector(testUpdateSuccessOnNextLaunch))
                        .targetting(self)
                    NSMenuItem(title: "Success (Unexpected)", action: #selector(testUnexpectedUpdateSuccessOnNextLaunch))
                        .targetting(self)
                    NSMenuItem(title: "Failure", action: #selector(testUpdateFailureOnNextLaunch))
                        .targetting(self)
                }
                NSMenuItem.separator()
            }
            if buildType.isAppStoreBuild {
                #if DEBUG
                NSMenuItem(title: "Set up App Store testing environment…", action: #selector(setupAppStoreTestingEnvironment))
                    .targetting(self)
                NSMenuItem(title: "Set metadata server URL…", action: #selector(setMetadataServerURL))
                    .targetting(self)
                NSMenuItem(title: "Reset metadata server URL", action: #selector(resetMetadataServerURL))
                    .targetting(self)
                metadataServerMenuItem
                NSMenuItem.separator()
                #endif
                forceUpdateAvailableMenuItem
                    .targetting(self)
                NSMenuItem(title: "Reset Debug Settings", action: #selector(resetDebugSettings))
                    .targetting(self)
                NSMenuItem.separator()
            }
            NSMenuItem(title: "Prompt Stage")
                .submenu(UpdatePromptStageDebugMenu())
        }
    }

    override func update() {
        forceUpdateAvailableMenuItem.state = debugSettings.forceUpdateAvailable ? .on : .off
        #if DEBUG
        updateMetadataServerMenuItem()
        #endif
        super.update()
    }

    @objc private func toggleForceUpdateAvailable() {
        debugSettings.forceUpdateAvailable.toggle()
    }

    @objc private func resetDebugSettings() {
        #if DEBUG
        let hadMetadataOverride = debugSettings.appStoreMetadataBaseURL != nil
        #endif
        debugSettings.reset()
        Application.appDelegate.updateController?.updatePromptStageTracker?.reevaluate()
        #if DEBUG
        if hadMetadataOverride {
            Application.appDelegate.updateController?.checkForUpdateSkippingRollout()
        }
        updateMetadataServerMenuItem()
        #endif
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc func simulateNewUser() {
        try? settings.set(1, for: \.installBuild)

        let alert = NSAlert()
        alert.messageText = "Simulating New User"
        alert.informativeText = "Install build metadata has been set. Close and reopen Settings for changes to take effect."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc func simulateLegacyUser() {
        try? settings.removeValue(for: \.installBuild)

        let alert = NSAlert()
        alert.messageText = "Simulating Legacy User"
        alert.informativeText = "Install build metadata has been cleared. Close and reopen Settings for changes to take effect."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc func testUpdateSuccessOnNextLaunch() {
        SparkleDebugHelper.configureExpectedUpdateSuccess()
    }

    @objc func testUpdateFailureOnNextLaunch() {
        SparkleDebugHelper.configureUpdateFailure()
    }

    @objc func testUnexpectedUpdateSuccessOnNextLaunch() {
        SparkleDebugHelper.configureUnexpectedUpdateSuccess()
    }

    @objc func showBrowserUpdatedPopover() {
        Application.appDelegate.updateController?.notificationPresenter.showUpdateNotification(for: .updated)
    }

    @objc func showCriticalUpdatePopover() {
        Application.appDelegate.updateController?.notificationPresenter.showUpdateNotification(for: .critical, areAutomaticUpdatesEnabled: true)
    }

    // MARK: - App Store Testing

    #if DEBUG
    @objc private func setupAppStoreTestingEnvironment() {
        do {
            let fileManager = FileManager.default
            guard let downloadsURL = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first,
                  let build = Int(AppVersion().buildNumber), (0...9_007_199_254_740_991).contains(build) else {
                throw NSError(domain: "AppStoreTesting", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "The Downloads folder or app build number is unavailable."])
            }
            let exportURL = downloadsURL.resolvingSymlinksInPath()
                .appendingPathComponent("ddg-appstore-update-testing", isDirectory: true)
            if fileManager.fileExists(atPath: exportURL.path) {
                let values = try exportURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values.isDirectory == true, values.isSymbolicLink != true else {
                    throw NSError(domain: "AppStoreTesting", code: 2,
                                  userInfo: [NSLocalizedDescriptionKey: "The export folder must be a regular directory, not a symbolic link."])
                }
            }
            try fileManager.createDirectory(at: exportURL, withIntermediateDirectories: true)
            let scriptURL = exportURL.appendingPathComponent("appstore-metadata-server.py")
            try AppStoreTestingResources.serverScript.write(to: scriptURL, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: scriptURL.path)
            let settings = try JSONSerialization.data(withJSONObject: [
                "installed_version": AppVersion().versionNumber,
                "installed_build": build
            ], options: [.prettyPrinted, .sortedKeys])
            try settings.write(to: exportURL.appendingPathComponent("appstore-test-settings.json"), options: .atomic)
            let readmeURL = exportURL.appendingPathComponent("README.md")
            try testingInstructions(exportURL: exportURL).write(to: readmeURL, atomically: true, encoding: .utf8)
            guard NSWorkspace.shared.open(readmeURL) else {
                throw NSError(domain: "AppStoreTesting", code: 3,
                              userInfo: [NSLocalizedDescriptionKey: "The instructions could not be opened automatically. Open \(readmeURL.path) in a text editor."])
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not export App Store metadata testing"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    private func testingInstructions(exportURL: URL) -> String {
        let quotedPath = "'" + exportURL.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        return """
        # App Store CDN metadata testing

        The script and its settings are exported here:
        \(exportURL.path)

        Open Terminal and run:

            cd \(quotedPath)
            python3 appstore-metadata-server.py

        Keep this Terminal open while testing. Press Ctrl+C there to stop the server.
        Python 3 must already be installed. If a server is already running, stop it before restarting this exported copy.
        If Python reports “Operation not permitted” while reading the exported files, allow your terminal app to access Downloads:
        System Settings → Privacy & Security → Files & Folders → iTerm (or Terminal) → Downloads Folder.
        Enable that permission for the terminal app running Python, then retry the command.

        ## Configure the Debug app

        - Ensure internal user state is on.
        - Debug → Feature Flag Overrides → Updates → enable moreProminentUpdates.
        - Debug → Updates → Set metadata server URL… → enter http://localhost:8765/.
        - Turn off Debug → Updates → Force Update Available.
        - Debug → Updates → Prompt Stage → Force Prompt Stage → choose Automatic.

        ## Configure offers

        Open http://localhost:8765/ to edit release metadata, choose presets, and apply the offered scenario.
        The app provides its actual version/build as the preset baseline; these values are not editable on the web page.
        Use the existing Debug prompt-clock controls to test timing.
        Applying a scenario changes the server response. Set the same metadata URL again to request a fresh app check.

        This server supplies metadata only. It never installs, launches, or updates an app.
        The normal update button continues opening Apple App Store.

        ## Finish

        Press Ctrl+C in the server Terminal, then choose Debug → Updates → Reset metadata server URL in the app.

        """
    }

    @objc private func setMetadataServerURL() {
        var currentURL = debugSettings.appStoreMetadataBaseURL ?? "http://localhost:8765/"
        var errorMessage: String?

        while true {
            let alert = NSAlert.customConfigurationAlert(configurationUrl: currentURL)
            alert.messageText = "Set metadata server URL:"
            alert.informativeText = errorMessage ?? "Enter a base URL. The app adds release_metadata.json to this URL."

            if alert.runModal() == .cancel {
                return
            }
            guard let textField = alert.accessoryView as? NSTextField else {
                return
            }

            currentURL = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let components = URLComponents(string: currentURL),
                  let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
                  let host = components.host, !host.isEmpty,
                  components.user == nil, components.password == nil,
                  components.query == nil, components.fragment == nil,
                  let url = components.url else {
                errorMessage = "Enter an HTTP or HTTPS base URL with a host and no credentials, query, or fragment."
                continue
            }
            guard !components.path.hasSuffix("release_metadata.json") else {
                errorMessage = "Enter the server's base URL, without release_metadata.json."
                continue
            }

            let baseURL = url.absoluteString
            debugSettings.appStoreMetadataBaseURL = baseURL.hasSuffix("/") ? baseURL : baseURL + "/"
            Application.appDelegate.updateController?.checkForUpdateSkippingRollout()
            updateMetadataServerMenuItem()
            return
        }
    }

    @objc private func resetMetadataServerURL() {
        debugSettings.appStoreMetadataBaseURL = nil
        Application.appDelegate.updateController?.checkForUpdateSkippingRollout()
        updateMetadataServerMenuItem()
    }

    private func updateMetadataServerMenuItem() {
        metadataServerMenuItem.title = "Metadata server: \(debugSettings.appStoreMetadataBaseURL ?? "default CDN")"
        metadataServerMenuItem.isEnabled = false
    }
    #endif

    // MARK: - Custom Feed URL

    private var customFeedURL: String? {
        get { try? settings.debugSparkleCustomFeedURL }
        set { try? settings.set(newValue, for: \.debugSparkleCustomFeedURL) }
    }

    private var sparkleUpdateController: (any SparkleCustomFeedURLProviding)? {
        Application.appDelegate.updateController as? any SparkleCustomFeedURLProviding
    }

    @objc func setCustomFeedURL() {
        var currentURL = customFeedURL ?? ""
        var errorMessage: String?

        while true {
            let alert = NSAlert.customConfigurationAlert(configurationUrl: currentURL)
            alert.messageText = "Set custom Sparkle feed URL:"

            if let error = errorMessage {
                alert.informativeText = error
            }

            if alert.runModal() == .cancel {
                return
            }

            guard let textField = alert.accessoryView as? NSTextField else {
                return
            }

            let trimmedURL = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmedURL.isEmpty {
                return
            }

            if !trimmedURL.lowercased().hasSuffix(".xml") {
                errorMessage = "⚠️ URL must end with .xml"
                currentURL = trimmedURL
                continue
            }

            sparkleUpdateController?.setCustomFeedURL(trimmedURL)
            return
        }
    }

    @objc func resetFeedURLToDefault() {
        sparkleUpdateController?.resetFeedURLToDefault()
    }

    // MARK: - Sparkle Testing Environment Setup

    @objc func setupSparkleTestingEnvironment() {
        // Prompt for private key
        guard let privateKeyBase64 = promptForPrivateKey() else {
            return
        }

        let fileManager = FileManager.default
        let desktopURL = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        let testingDir = desktopURL.appendingPathComponent("ddg-update-testing")

        do {
            // Create directory
            try fileManager.createDirectory(at: testingDir, withIntermediateDirectories: true)

            // Create serve_update.py
            let scriptURL = testingDir.appendingPathComponent("serve_update.py")
            try SparkleTestingResources.serverScript.write(to: scriptURL, atomically: true, encoding: .utf8)

            // Create README.md
            let readmeURL = testingDir.appendingPathComponent("README.md")
            try SparkleTestingResources.readme.write(to: readmeURL, atomically: true, encoding: .utf8)

            // Zip the running app
            let appBundlePath = Bundle.main.bundlePath
            let zipURL = testingDir.appendingPathComponent("DuckDuckGo.app.zip")

            // Remove existing zip if present
            try? fileManager.removeItem(at: zipURL)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-c", "-k", "--keepParent", appBundlePath, zipURL.path]
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus != 0 {
                throw NSError(domain: "UpdatesDebugMenu", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create zip file"])
            }

            // Sign the zip file
            let signature = try signFile(at: zipURL, withPrivateKeyBase64: privateKeyBase64)
            let zipSize = try fileManager.attributesOfItem(atPath: zipURL.path)[.size] as? Int ?? 0

            // Create appcast2.xml with the signature
            let appcastURL = testingDir.appendingPathComponent("appcast2.xml")
            let appcastContent = SparkleTestingResources.appcastXML(signature: signature, fileSize: zipSize)
            try appcastContent.write(to: appcastURL, atomically: true, encoding: .utf8)

            // Open README.md
            NSWorkspace.shared.open(readmeURL)

        } catch {
            Logger.updates.error("Failed to set up Sparkle testing environment: \(error.localizedDescription)")
            let alert = NSAlert()
            alert.messageText = "Failed to set up testing environment"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    private func promptForPrivateKey() -> String? {
        let alert = NSAlert()
        alert.messageText = "Private key for testing Sparkle updates"
        alert.informativeText = "Paste the base64-encoded EdDSA private key (64 bytes).\nThis key is stored in the company secure location."
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let textField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 400, height: 24))
        textField.placeholderString = "Base64 private key..."
        alert.accessoryView = textField

        if alert.runModal() == .alertFirstButtonReturn {
            let key = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty {
                return key
            }
        }
        return nil
    }

    private func signFile(at url: URL, withPrivateKeyBase64: String) throws -> String {
        // Decode the private key (64 bytes: 32-byte seed + 32-byte public key)
        guard let privateKeyData = Data(base64Encoded: withPrivateKeyBase64),
              privateKeyData.count == 64 else {
            throw NSError(domain: "UpdatesDebugMenu", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid private key format. Expected 64 bytes base64-encoded."])
        }

        // Extract the 32-byte seed (first 32 bytes)
        let seed = privateKeyData.prefix(32)

        // Create the signing key from the seed
        let signingKey = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)

        // Read the file data
        let fileData = try Data(contentsOf: url)

        // Sign the data
        let signature = try signingKey.signature(for: fileData)

        // Return base64-encoded signature
        return signature.base64EncodedString()
    }

}

// MARK: - Sparkle Testing Resources

private enum SparkleTestingResources {

    static let readme = """
    # Sparkle Update Testing

    This folder contains everything needed to test Sparkle updates locally.

    ## Step 1: Start the Local Server

    Open Terminal and run these two commands:

        cd ~/Desktop/ddg-update-testing
        python3 serve_update.py

    The first time you run this, it will:
    - Generate a security certificate
    - Ask for your Mac password to trust the certificate

    Keep this Terminal window open while testing.

    ## Step 2: Point the App to Your Local Server

    In the DuckDuckGo app:
    1. Open the Debug menu (in the menu bar)
    2. Go to Updates → Set custom feed URL…
    3. Enter: https://localhost:8443/appcast2.xml
    4. Click OK

    ## Step 3: Test the Update

    In the DuckDuckGo app:
    1. Open the DuckDuckGo menu (in the menu bar)
    2. Click "Check for Updates"
    3. The app should find "Version 99.0.0" and offer to install it

    ## When You're Done Testing

    ### Reset the App to Normal Updates

    In the DuckDuckGo app:
    1. Debug menu → Updates → Reset feed URL to default

    ### Remove the Test Certificate

    Open Terminal and run:

        sudo security delete-certificate -c "ddg-sparkle-testing" /Library/Keychains/System.keychain

    ### Stop the Server

    In the Terminal window running the server, press Ctrl+C.

    ### Delete This Folder (Optional)

    You can safely delete the entire `ddg-update-testing` folder from your Desktop.

    ## What's in This Folder

    - `serve_update.py` - A simple web server that serves the update files
    - `appcast2.xml` - Describes the fake update (version 99.0.0)
    - `DuckDuckGo.app.zip` - The app that will be "installed" as the update
    - `README.md` - This file
    """

    static func appcastXML(signature: String, fileSize: Int) -> String {
        """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
          <channel>
            <title>DuckDuckGo</title>
            <item>
              <title>Version 99.0.0</title>
              <pubDate>Mon, 01 Jan 2099 12:00:00 +0000</pubDate>
              <sparkle:version>9999</sparkle:version>
              <sparkle:shortVersionString>99.0.0</sparkle:shortVersionString>
              <description><![CDATA[
                <h3>What's new</h3>
                <ul>
                  <li>Test update for local Sparkle testing</li>
                </ul>
              ]]></description>
              <enclosure url="https://localhost:8443/DuckDuckGo.app.zip"
                         length="\(fileSize)"
                         type="application/octet-stream"
                         sparkle:edSignature="\(signature)"/>
            </item>
          </channel>
        </rss>
        """
    }

    static let serverScript = #"""
    #!/usr/bin/env python3
    """
    Simple HTTPS server for testing Sparkle updates locally.

    Usage:
        1. Run: python3 serve_update.py
        2. Server starts at https://localhost:8443
        3. Certificate is auto-installed on first run (requires admin password)
    """

    import http.server
    import ssl
    import os
    import subprocess
    import sys

    PORT = 8443
    CERT_FILE = "ddg-sparkle-testing.pem"
    KEY_FILE = "ddg-sparkle-testing-key.pem"
    CERT_NAME = "ddg-sparkle-testing"


    def generate_self_signed_cert():
        """Generate a self-signed certificate for localhost.

        Returns: (exists, newly_generated) tuple
        """
        if os.path.exists(CERT_FILE) and os.path.exists(KEY_FILE):
            return (True, False)

        print("Generating self-signed certificate...")

        cmd = [
            "openssl", "req", "-x509", "-newkey", "rsa:4096",
            "-keyout", KEY_FILE,
            "-out", CERT_FILE,
            "-days", "365",
            "-nodes",
            "-subj", f"/CN={CERT_NAME}",
            "-addext", "subjectAltName=DNS:localhost,IP:127.0.0.1"
        ]

        try:
            subprocess.run(cmd, check=True, capture_output=True)
            print(f"Certificate generated: {CERT_FILE}")
            return (True, True)
        except subprocess.CalledProcessError as e:
            print(f"Error generating certificate: {e.stderr.decode()}")
            return (False, False)


    def is_cert_trusted():
        """Check if the certificate is trusted in the system keychain."""
        try:
            result = subprocess.run(
                ["security", "find-certificate", "-c", CERT_NAME, "/Library/Keychains/System.keychain"],
                capture_output=True
            )
            return result.returncode == 0
        except Exception:
            return False


    def install_cert():
        """Install the certificate to the system keychain (requires admin)."""
        cert_path = os.path.abspath(CERT_FILE)
        print()
        print("The certificate needs to be trusted by your system.")
        print("You will be prompted for your admin password.")
        print()

        try:
            result = subprocess.run(
                ["sudo", "security", "add-trusted-cert", "-d", "-r", "trustRoot",
                 "-k", "/Library/Keychains/System.keychain", cert_path]
            )
            return result.returncode == 0
        except Exception as e:
            print(f"Error installing certificate: {e}")
            return False


    def delete_old_cert():
        """Remove existing certificate with same name from keychain."""
        print("Removing old certificate from keychain if present...")
        subprocess.run(
            ["sudo", "security", "delete-certificate", "-c", CERT_NAME,
             "/Library/Keychains/System.keychain"],
            capture_output=True  # Ignore errors if not found
        )


    def run_server():
        """Run the HTTPS server."""
        # Generate certificate if needed
        (success, newly_generated) = generate_self_signed_cert()
        if not success:
            sys.exit(1)

        # If we just generated a new cert, remove any old one from keychain first
        if newly_generated:
            delete_old_cert()

        # Check if certificate is trusted
        if not is_cert_trusted():
            print("Certificate is not yet trusted.")
            if not install_cert():
                print()
                print("Failed to install certificate.")
                print("You can install it manually with:")
                print(f"  sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain {os.path.abspath(CERT_FILE)}")
                sys.exit(1)

            # Verify installation
            if not is_cert_trusted():
                print()
                print("Certificate installation could not be verified.")
                print("Please try installing manually:")
                print(f"  sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain {os.path.abspath(CERT_FILE)}")
                sys.exit(1)

        print()
        print(f"Certificate is trusted: {CERT_FILE}")

        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(CERT_FILE, KEY_FILE)

        handler = http.server.SimpleHTTPRequestHandler
        server = http.server.HTTPServer(("localhost", PORT), handler)
        server.socket = context.wrap_socket(server.socket, server_side=True)

        print()
        print(f"Serving HTTPS on https://localhost:{PORT}")
        print(f"Feed URL: https://localhost:{PORT}/appcast2.xml")
        print()
        print("Press Ctrl+C to stop")

        try:
            server.serve_forever()
        except KeyboardInterrupt:
            print("\nServer stopped")


    if __name__ == "__main__":
        run_server()
    """#

}

// MARK: - App Store Testing Resources

#if DEBUG
private enum AppStoreTestingResources {
    static let serverScript = #"""
    #!/usr/bin/env python3
    """Local App Store CDN metadata server and admin page (Python standard library).

    Run the exported script from Terminal:
        python3 appstore-metadata-server.py

    The adjacent appstore-test-settings.json contains the real app's initial
    installed_version and installed_build. No Git checkout or preparation step is
    required. Debug app request headers refresh this hidden preset baseline.
    For development, explicit --installed-version and --installed-build values can
    replace that initial configuration. Run --self-test for HTTP contract tests.

    Open the printed admin URL to change offered versions, critical-update flags,
    and rollout release dates. Apply changes only the server's metadata; it does
    not install, launch, stop, or configure an app. Keep this Terminal running and
    press Ctrl+C to stop the server. Scenarios are held in memory until it exits.

    In the Debug app enable internal-user state and moreProminentUpdates under
    Debug > Feature Flag Overrides > Updates. Choose Debug > Updates > Set metadata
    server URL… and enter the printed URL. Turn off Force Update Available and
    select Debug > Updates > Prompt Stage > Force Prompt Stage > Automatic.
    After applying a scenario, set the same URL again to request a fresh check.
    Use the existing Debug prompt-clock controls to exercise timing.

    For HTTPS, pass --cert and --key for an already trusted certificate. No
    certificates are installed. When finished choose Debug > Updates > Reset
    metadata server URL to restore the normal CDN.
    """

    import argparse
    import copy
    from datetime import datetime, timedelta, timezone
    from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
    import json
    from pathlib import Path
    import re
    import ssl
    import threading


    PANEL = r'''<!doctype html>
    <html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
    <title>App Store update lab</title>
    <style>
    :root{font:15px -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;color:#202331;background:#f3f4f7}
    *{box-sizing:border-box}body{max-width:1060px;margin:42px auto;padding:0 24px}h1{font-size:32px;margin-bottom:8px}
    h2{font-size:18px;margin:0 0 20px}p{line-height:1.6;color:#606675}.tag{color:#3564dc;font-weight:600;font-size:12px;letter-spacing:1px}
    .card{background:white;border:1px solid #e1e4ec;border-radius:14px;padding:24px;margin:20px 0}.grid{display:grid;grid-template-columns:1fr 1fr;gap:20px}
    label{display:block;font-size:13px;font-weight:600;margin:14px 0 6px}input{width:100%;padding:10px;border:1px solid #c9ceda;border-radius:7px;font:inherit}
    input[type=checkbox]{width:auto;margin-right:8px}.check{display:flex;align-items:center;gap:6px}.check label{margin:0}
    button{cursor:pointer;border:1px solid #ccd2df;border-radius:8px;background:white;padding:10px 15px;font:inherit;margin:4px 4px 4px 0}
    button:hover{background:#edf2ff}.primary{background:#315cda;color:white;border-color:#315cda}.primary:hover{background:#2449b8}
    code,pre{font:12px ui-monospace,SFMono-Regular,monospace}pre{background:#f7f8fb;padding:16px;border-radius:8px;overflow:auto;line-height:1.6}
    .hint{font-size:13px}#status{display:block;min-height:25px;margin-top:10px;color:#245a38}#status.error{color:#ba2828}
    table{width:100%;border-collapse:collapse;font-size:13px}td,th{text-align:left;border-bottom:1px solid #edf0f5;padding:10px 6px}
    fieldset{border:0;padding:0;margin:0}fieldset:disabled{opacity:.4}@media(max-width:700px){.grid{grid-template-columns:1fr}}
    </style>
    <div class="tag">LOCAL TEST TOOL</div><h1>App Store update lab</h1>
    <p>Choose what the CDN offers. Apply a scenario, then relaunch the test app to fetch it.</p>
    <div class="card"><h2>Connect your Debug app</h2>
    <p class="hint">Choose Debug → Updates → Set metadata server URL… and enter:</p><pre id="connection"></pre>
    <p class="hint">Turn off “Force Update Available” and select “Automatic” for the forced prompt stage.
    Use the app’s prompt-clock controls to test timing. HTTPS needs an already trusted certificate.</p></div>
    <form id="editor">
    <div class="card"><h2>Release presets</h2>
    <p class="hint">Load a preset, adjust the offered release details, then apply it. This page only changes CDN metadata.</p>
    <div id="presets"></div></div>
    <div class="grid"><div class="card"><h2>Latest release</h2><div id="latest-fields"></div></div>
    <div class="card"><h2>Rolling release</h2><div class="check"><input id="rolling" type="checkbox"><label for="rolling">Offer a rolling release</label></div>
    <fieldset id="available-fields" disabled></fieldset></div></div>
    <button class="primary" type="submit">Apply scenario</button><button id="reset" type="button">Reset scenario</button>
    <output id="status" aria-live="polite"></output></form>
    <div class="grid"><div class="card"><h2>Currently served JSON</h2><pre id="json"></pre></div>
    <div class="card"><h2>Recent metadata requests</h2><p class="hint">Confirms a fetch, not that the app displayed a prompt.</p>
    <table><thead><tr><th>Time</th><th>Latest</th><th>Rolling</th></tr></thead><tbody id="requests"></tbody></table></div></div>
    <script>
    const $=id=>document.getElementById(id);
    let baseline;
    for(const prefix of ['latest','available']){
      const box=$(prefix+'-fields');
      for(const [key,label,type] of [['latest_version','Version','text'],['build_number','Build','number'],['release_date','Release date (UTC, ISO 8601)','text']]){
        const id=prefix+'-'+key,l=document.createElement('label'),input=document.createElement('input');
        l.htmlFor=id;l.textContent=label;input.id=id;input.type=type;input.required=true;
        if(type==='number'){input.min=0;input.step=1;}box.append(l,input);
      }
      const l=document.createElement('label'),input=document.createElement('input');
      input.id=prefix+'-is_critical';input.type='checkbox';l.append(input,document.createTextNode('Critical update'));box.append(l);
    }
    const stamp=days=>new Date(Date.now()-days*86400000).toISOString().replace(/\.\d{3}Z$/,'Z');
    function release(version,build,date=stamp(30),critical=false){return {latest_version:version,build_number:build,release_date:date,is_critical:critical};}
    function fill(prefix,data){for(const [key,value] of Object.entries(data)){
      const input=$(prefix+'-'+key);if(input.type==='checkbox')input.checked=value;else input.value=value;
    }}
    function read(prefix){return release($(prefix+'-latest_version').value,Number($(prefix+'-build_number').value),$(prefix+'-release_date').value,$(prefix+'-is_critical').checked);}
    function toggleRolling(){$('available-fields').disabled=!$('rolling').checked;}
    $('rolling').onchange=toggleRolling;
    function preset(kind){
      if(!baseline){status('Waiting for server state. Try again shortly.',true);return;}
      const {version,build}=baseline,parts=version.split('.');
      parts[parts.length-1]=String(Number(parts[parts.length-1])+1);
      fill('latest',release(kind==='current'||kind.startsWith('rollout')?version:parts.join('.'),kind==='current'||kind.startsWith('rollout')?build:build+1,stamp(30),kind==='critical'));
      fill('available',release(parts.join('.'),build+1,stamp(kind==='rollout-recent'?0:30)));
      $('rolling').checked=kind.startsWith('rollout');toggleRolling();
      status('Preset loaded. Apply it to change the server response.');
    }
    for(const [kind,title] of [['current','Up to date'],['regular','Regular update'],['critical','Critical update'],['rollout-recent','Rollout just started'],['rollout-aged','Rollout aged 30 days']]){
      const b=document.createElement('button');b.type='button';b.textContent=title;b.onclick=()=>preset(kind);$('presets').append(b);
    }
    function status(message,error=false){$('status').textContent=message;$('status').className=error?'error':'';}
    async function api(path,body){
      const response=await fetch(path,body===undefined?{cache:'no-store'}:{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
      const data=await response.json();if(!response.ok)throw Error(data.error);return data;
    }
    function show(data,editor=false){
      baseline={version:data.scenario.installed_version,build:data.scenario.installed_build};
      $('connection').textContent=location.origin+'/';
      $('json').textContent=JSON.stringify(data.scenario.metadata,null,2);
      $('requests').replaceChildren();
      for(const row of data.requests.slice().reverse()){
        const tr=document.createElement('tr');for(const value of [row.time,row.latest,row.available||'—']){const td=document.createElement('td');td.textContent=value;tr.append(td);}$('requests').append(tr);
      }
      if(editor){
        fill('latest',data.scenario.metadata.latest_appstore_version);
        fill('available',data.scenario.metadata.available_appstore_version||release(data.scenario.installed_version,data.scenario.installed_build));
        $('rolling').checked=!!data.scenario.metadata.available_appstore_version;toggleRolling();
      }
    }
    $('editor').onsubmit=async event=>{event.preventDefault();try{
      const metadata={latest_appstore_version:read('latest')};if($('rolling').checked)metadata.available_appstore_version=read('available');
      show(await api('/api/scenario',{metadata}));
      status('Applied. Relaunch the test app and watch for its metadata request.');
    }catch(error){status(error.message,true);}};
    $('reset').onclick=async()=>{try{show(await api('/api/reset',{}),true);status('Initial scenario restored.');}catch(error){status(error.message,true);}};
    api('/api/state').then(data=>show(data,true)).catch(error=>status(error.message,true));
    setInterval(()=>api('/api/state').then(data=>show(data)).catch(error=>status(error.message,true)),2000);
    </script></html>'''


    def validate_version(value):
        if not isinstance(value, str) or len(value) > 80 or not re.fullmatch(r"\d+(?:\.\d+){0,3}", value, re.ASCII):
            raise ValueError("Version must contain one to four numeric components, such as 1.216.0.")
        if any(int(part) > 9223372036854775807 for part in value.split(".")):
            raise ValueError("Version components exceed the supported integer range.")


    def validate_build(value):
        if type(value) is not int or not 0 <= value <= 9007199254740991:
            raise ValueError("Build must be a nonnegative integer no larger than 9007199254740991.")


    def validate_scenario(scenario):
        if not isinstance(scenario, dict):
            raise ValueError("Expected a scenario object.")
        validate_version(scenario.get("installed_version"))
        validate_build(scenario.get("installed_build"))
        metadata = scenario.get("metadata")
        if not isinstance(metadata, dict) or not isinstance(metadata.get("latest_appstore_version"), dict):
            raise ValueError("A latest App Store release is required.")
        for name in ("latest_appstore_version", "available_appstore_version"):
            if name not in metadata:
                continue
            release = metadata[name]
            if not isinstance(release, dict):
                raise ValueError("Release entries must be objects.")
            validate_version(release.get("latest_version"))
            validate_build(release.get("build_number"))
            if type(release.get("is_critical")) is not bool:
                raise ValueError("Critical update must be true or false.")
            date = release.get("release_date")
            if not isinstance(date, str) or not re.fullmatch(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ", date, re.ASCII):
                raise ValueError("Release date must use UTC ISO 8601, such as 2026-11-11T12:00:00Z.")
            try:
                datetime.strptime(date, "%Y-%m-%dT%H:%M:%SZ")
            except ValueError as error:
                raise ValueError("Release date is not a valid calendar date.") from error


    def initial_scenario(version, build):
        scenario = {
            "installed_version": version,
            "installed_build": build,
            "metadata": {"latest_appstore_version": {
                "latest_version": version,
                "build_number": build,
                "release_date": (datetime.now(timezone.utc) - timedelta(days=30)).strftime("%Y-%m-%dT%H:%M:%SZ"),
                "is_critical": False,
            }},
        }
        validate_scenario(scenario)
        return scenario


    class MetadataServer(ThreadingHTTPServer):
        def __init__(self, port, scenario):
            self.initial = copy.deepcopy(scenario)
            self.scenario = copy.deepcopy(scenario)
            self.requests = []
            self.lock = threading.Lock()
            super().__init__(("127.0.0.1", port), Handler)


    class Handler(BaseHTTPRequestHandler):
        def reply(self, status, data, content_type="application/json"):
            body = data.encode() if isinstance(data, str) else json.dumps(data, allow_nan=False).encode()
            self.send_response(status)
            self.send_header("Content-Type", content_type + "; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def state(self):
            return {"scenario": copy.deepcopy(self.server.scenario), "requests": list(self.server.requests)}

        def do_GET(self):
            path = self.path.split("?", 1)[0]
            if path == "/":
                self.reply(200, PANEL, "text/html")
            elif path == "/api/state":
                with self.server.lock:
                    state = self.state()
                self.reply(200, state)
            elif path == "/release_metadata.json":
                version = self.headers.get("X-DDG-Test-App-Version")
                build = self.headers.get("X-DDG-Test-App-Build")
                try:
                    validate_version(version)
                    if build is None or not re.fullmatch(r"[0-9]+", build):
                        raise ValueError("Missing or invalid test app build.")
                    build = int(build)
                    validate_build(build)
                except ValueError:
                    version = None
                with self.server.lock:
                    if version is not None:
                        self.server.scenario["installed_version"] = version
                        self.server.scenario["installed_build"] = build
                    metadata = copy.deepcopy(self.server.scenario["metadata"])
                    self.server.requests.append({
                        "time": datetime.now(timezone.utc).strftime("%H:%M:%S UTC"),
                        "latest": metadata["latest_appstore_version"]["latest_version"],
                        "available": metadata.get("available_appstore_version", {}).get("latest_version"),
                    })
                    self.server.requests = self.server.requests[-20:]
                self.reply(200, metadata)
            else:
                self.reply(404, {"error": "Not found"})

        def do_POST(self):
            # A page on another origin must not be able to change the local offer.
            origin = self.headers.get("Origin")
            if origin and origin not in ("http://" + self.headers.get("Host", ""), "https://" + self.headers.get("Host", "")):
                self.reply(403, {"error": "Use the local control panel to change the scenario."})
                return
            try:
                length = int(self.headers.get("Content-Length", "0"))
                if not 0 < length <= 16384:
                    raise ValueError("Expected a JSON body no larger than 16 KiB.")
                payload = json.loads(self.rfile.read(length))
                if self.path == "/api/scenario":
                    if not isinstance(payload, dict):
                        raise ValueError("Expected a scenario object.")
                    with self.server.lock:
                        candidate = copy.deepcopy(self.server.scenario)
                    candidate["metadata"] = payload.get("metadata")
                    validate_scenario(candidate)
                    metadata = candidate["metadata"]
                elif self.path == "/api/reset":
                    metadata = copy.deepcopy(self.server.initial["metadata"])
                else:
                    self.reply(404, {"error": "Not found"})
                    return
            except (ValueError, UnicodeError) as error:
                self.reply(400, {"error": str(error)})
                return
            with self.server.lock:
                self.server.scenario["metadata"] = metadata
                state = self.state()
            self.reply(200, state)


    def self_test():
        """Exercise the actual HTTP contract, including rejected updates staying atomic."""
        import select
        import shutil
        import signal
        import subprocess
        import sys
        import tempfile
        import unittest
        from urllib.error import HTTPError
        from urllib.request import Request, urlopen

        class ContractTests(unittest.TestCase):
            def test_exported_startup_without_checkout(self):
                with tempfile.TemporaryDirectory() as temporary:
                    root = Path(temporary)
                    standalone = root / "appstore-metadata-server.py"
                    shutil.copyfile(__file__, standalone)
                    settings = root / "appstore-test-settings.json"
                    settings.write_text(json.dumps({"installed_version": "1.216.0", "installed_build": 872}))
                    process = subprocess.Popen([sys.executable, str(standalone), "--port", "0"], cwd="/",
                                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
                    try:
                        self.assertTrue(select.select([process.stdout], [], [], 10)[0], "Exported server did not start")
                        line = process.stdout.readline().strip()
                        self.assertTrue(line.startswith("Control panel: http://localhost:"), line)
                        base = line.removeprefix("Control panel: ")
                        with urlopen(base + "api/state", timeout=5) as response:
                            state = json.load(response)
                        self.assertEqual(set(state), {"scenario", "requests"})
                        self.assertEqual(state["scenario"]["installed_version"], "1.216.0")
                        self.assertEqual(state["scenario"]["installed_build"], 872)
                        with urlopen(base + "release_metadata.json", timeout=5) as response:
                            self.assertEqual(json.load(response), state["scenario"]["metadata"])
                        process.send_signal(signal.SIGINT)
                        self.assertEqual(process.wait(timeout=5), 0)
                    finally:
                        if process.poll() is None:
                            process.terminate()
                        try:
                            process.wait(timeout=5)
                        except subprocess.TimeoutExpired:
                            process.kill()
                            process.wait(timeout=5)
                        process.stdout.close()
                    settings.write_text(json.dumps({"installed_version": "1.216.0", "installed_build": 9007199254740992}))
                    invalid = subprocess.run([sys.executable, str(standalone), "--port", "0"], cwd="/",
                                             capture_output=True, text=True, timeout=5)
                    self.assertNotEqual(invalid.returncode, 0)
                    self.assertIn("Build must be", invalid.stderr)

            def test_http_contract(self):
                self.assertEqual(startup_scenario("1", 0)["installed_version"], "1")
                server = MetadataServer(0, initial_scenario("1.216.0", 872))
                thread = threading.Thread(target=server.serve_forever, daemon=True)
                thread.start()
                base = "http://127.0.0.1:" + str(server.server_port)

                def request(path, payload=None, headers=None):
                    data = None if payload is None else json.dumps(payload).encode()
                    return urlopen(Request(base + path, data=data, headers=headers or {}), timeout=5)

                try:
                    with request("/") as response:
                        page = response.read()
                        self.assertIn(b"App Store update lab", page)
                        self.assertNotIn(b'id="installed_version"', page)
                        self.assertNotIn(b'id="installed_build"', page)
                    for route in ("/artifacts/app.zip", "/install", "/launch", "/api/stop"):
                        with self.assertRaises(HTTPError) as raised:
                            request(route)
                        self.assertEqual(raised.exception.code, 404)
                        with self.assertRaises(HTTPError) as raised:
                            request(route, {})
                        self.assertEqual(raised.exception.code, 404)
                    with request("/release_metadata.json", headers={
                        "X-DDG-Test-App-Version": "1.300.0", "X-DDG-Test-App-Build": "999",
                    }) as response:
                        self.assertEqual(response.headers["Cache-Control"], "no-store")
                        self.assertEqual(json.load(response)["latest_appstore_version"]["build_number"], 872)
                    with request("/api/state") as response:
                        learned = json.load(response)["scenario"]
                        self.assertEqual(learned["installed_version"], "1.300.0")
                        self.assertEqual(learned["installed_build"], 999)
                    scenario = initial_scenario("1.216.0", 872)
                    scenario["metadata"]["latest_appstore_version"]["latest_version"] = "1.301.0"
                    scenario["metadata"]["available_appstore_version"] = {
                        "latest_version": "1.217.0", "build_number": 873,
                        "release_date": "2026-11-11T12:00:00Z", "is_critical": True,
                    }
                    with request("/api/scenario", scenario) as response:
                        self.assertEqual(response.status, 200)
                        self.assertEqual(json.load(response)["scenario"]["installed_version"], "1.300.0")
                    with request("/release_metadata.json", headers={
                        "X-DDG-Test-App-Version": "not-a-version", "X-DDG-Test-App-Build": "1000",
                    }) as response:
                        self.assertEqual(json.load(response), scenario["metadata"])
                    for key, bad in (("build_number", True), ("build_number", 9007199254740992), ("latest_version", "bad"),
                                     ("release_date", "2026-02-30T12:00:00Z"), ("is_critical", "yes")):
                        invalid = copy.deepcopy(scenario)
                        invalid["metadata"]["available_appstore_version"][key] = bad
                        with self.assertRaises(HTTPError) as raised:
                            request("/api/scenario", invalid)
                        self.assertEqual(raised.exception.code, 400)
                    with request("/release_metadata.json") as response:
                        self.assertEqual(json.load(response), scenario["metadata"])
                    with self.assertRaises(HTTPError) as raised:
                        request("/api/reset", {}, {"Origin": "https://example.com"})
                    self.assertEqual(raised.exception.code, 403)
                    with request("/api/state") as response:
                        state = json.load(response)
                        self.assertEqual(len(state["requests"]), 3)
                        self.assertEqual(state["scenario"]["installed_version"], "1.300.0")
                        self.assertEqual(state["scenario"]["installed_build"], 999)
                    with request("/api/reset", {}) as response:
                        reset = json.load(response)["scenario"]
                        self.assertNotIn("available_appstore_version", reset["metadata"])
                        self.assertEqual(reset["installed_version"], "1.300.0")
                        self.assertEqual(reset["installed_build"], 999)
                finally:
                    server.shutdown()
                    thread.join(timeout=5)
                    server.server_close()

        result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(ContractTests))
        raise SystemExit(0 if result.wasSuccessful() else 1)


    def startup_scenario(installed_version=None, installed_build=None):
        settings = {}
        if installed_version is None or installed_build is None:
            path = Path(__file__).resolve().with_name("appstore-test-settings.json")
            try:
                settings = json.loads(path.read_text())
            except FileNotFoundError as error:
                raise ValueError("Export the server with appstore-test-settings.json, or provide --installed-version and --installed-build.") from error
            if not isinstance(settings, dict):
                raise ValueError("appstore-test-settings.json must contain an app version/build object.")
        version = installed_version if installed_version is not None else settings.get("installed_version")
        build = installed_build if installed_build is not None else settings.get("installed_build")
        return initial_scenario(version, build)


    def main():
        parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
        parser.add_argument("--port", type=int, default=8765)
        parser.add_argument("--installed-version", default=None, help="Preset baseline version; does not modify the app")
        parser.add_argument("--installed-build", type=int, default=None, help="Preset baseline build; does not modify the app")
        parser.add_argument("--cert", type=Path, help="Existing trusted HTTPS certificate (PEM)")
        parser.add_argument("--key", type=Path, help="Matching HTTPS private key (PEM)")
        parser.add_argument("--self-test", action="store_true")
        args = parser.parse_args()
        if args.self_test:
            self_test()
        if bool(args.cert) != bool(args.key):
            parser.error("Provide both --cert and --key for HTTPS.")
        try:
            server = MetadataServer(args.port, startup_scenario(args.installed_version, args.installed_build))
            if args.cert:
                context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
                context.load_cert_chain(str(args.cert.expanduser()), str(args.key.expanduser()))
                server.socket = context.wrap_socket(server.socket, server_side=True)
        except (OSError, ValueError) as error:
            parser.error(str(error))
        base = f"{'https' if args.cert else 'http'}://localhost:{server.server_port}/"
        print(f"Control panel: {base}\nMetadata: {base}release_metadata.json", flush=True)
        print(f"Debug > Updates > Set metadata server URL…: {base}", flush=True)
        print("Use --cert and --key for HTTPS with an already trusted certificate. Ctrl+C stops the server.", flush=True)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass
        finally:
            server.server_close()


    if __name__ == "__main__":
        main()

    """#
}
#endif
