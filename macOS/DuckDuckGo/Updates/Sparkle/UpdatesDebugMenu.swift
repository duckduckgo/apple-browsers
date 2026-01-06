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

import AppKit
import AIChat
import Common
import os.log

final class UpdatesDebugMenu: NSMenu {
    init() {
        super.init(title: "")

        buildItems {
#if SPARKLE_ALLOWS_UNSIGNED_UPDATES
            NSMenuItem(title: "Set custom feed URL…", action: #selector(setCustomFeedURL))
                .targetting(self)
            NSMenuItem(title: "Reset feed URL to default", action: #selector(resetFeedURLToDefault))
                .targetting(self)
            NSMenuItem(title: "Set up Sparkle testing environment…", action: #selector(setupSparkleTestingEnvironment))
                .targetting(self)
            NSMenuItem.separator()
#endif
            NSMenuItem(title: "Expire current update", action: #selector(expireCurrentUpdate))
                .targetting(self)
            NSMenuItem(title: "Reset last update check", action: #selector(resetLastUpdateCheck))
                .targetting(self)
            NSMenuItem.separator()
            NSMenuItem(title: "Show Browser Updated Popover", action: #selector(showBrowserUpdatedPopover))
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
        }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Menu State Update

    @UserDefaultsWrapper(key: .updateValidityStartDate, defaultValue: nil)
    var updateValidityStartDate: Date?

    @objc func expireCurrentUpdate() {
        updateValidityStartDate = .distantPast
    }

    @UserDefaultsWrapper(key: .pendingUpdateSince, defaultValue: .distantPast)
    private var pendingUpdateSince: Date

    @objc func resetLastUpdateCheck() {
        pendingUpdateSince = .distantPast
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
        let presenter = UpdateNotificationPresenter()
        presenter.showUpdateNotification(
            icon: NSImage.successCheckmark,
            text: UserText.browserUpdatedNotification,
            buttonText: UserText.viewDetails
        )
    }

#if SPARKLE_ALLOWS_UNSIGNED_UPDATES
    // MARK: - Custom Feed URL

    @UserDefaultsWrapper(key: .debugSparkleCustomFeedURL)
    private var customFeedURL: String?

    private var sparkleUpdateController: SparkleUpdateController? {
        Application.appDelegate.updateController as? SparkleUpdateController
    }

    @objc func setCustomFeedURL() {
        let currentURL = customFeedURL ?? ""
        let alert = NSAlert.customConfigurationAlert(configurationUrl: currentURL)
        alert.messageText = "Set custom Sparkle feed URL:"

        if alert.runModal() != .cancel {
            guard let textField = alert.accessoryView as? NSTextField,
                  !textField.stringValue.isEmpty else {
                return
            }
            sparkleUpdateController?.setCustomFeedURL(textField.stringValue)
        }
    }

    @objc func resetFeedURLToDefault() {
        sparkleUpdateController?.resetFeedURLToDefault()
    }

    // MARK: - Sparkle Testing Environment Setup

    @objc func setupSparkleTestingEnvironment() {
        let fileManager = FileManager.default
        let desktopURL = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        let testingDir = desktopURL.appendingPathComponent("ddg-update-testing")

        do {
            // Create directory
            try fileManager.createDirectory(at: testingDir, withIntermediateDirectories: true)

            // Create serve_update.py
            let scriptURL = testingDir.appendingPathComponent("serve_update.py")
            try SparkleTestingResources.serverScript.write(to: scriptURL, atomically: true, encoding: .utf8)

            // Create appcast2.xml
            let appcastURL = testingDir.appendingPathComponent("appcast2.xml")
            try SparkleTestingResources.appcastXML.write(to: appcastURL, atomically: true, encoding: .utf8)

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
#endif

}

#if SPARKLE_ALLOWS_UNSIGNED_UPDATES
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

        sudo security delete-certificate -c "ddd-sparkle-testing" /Library/Keychains/System.keychain

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

    static let appcastXML = """
    <?xml version="1.0" encoding="utf-8"?>
    <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
      <channel>
        <title>DuckDuckGo</title>
        <item>
          <title>Version 99.0.0</title>
          <pubDate>Mon, 06 Jan 2026 12:00:00 +0000</pubDate>
          <sparkle:version>9999</sparkle:version>
          <sparkle:shortVersionString>99.0.0</sparkle:shortVersionString>
          <description><![CDATA[
            <ul>
              <li>Test update for local Sparkle testing</li>
            </ul>
          ]]></description>
          <enclosure url="https://localhost:8443/DuckDuckGo.app.zip" length="200000000" type="application/octet-stream"/>
        </item>
      </channel>
    </rss>
    """

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
    CERT_FILE = "ddd-sparkle-testing.pem"
    KEY_FILE = "ddd-sparkle-testing-key.pem"
    CERT_NAME = "ddd-sparkle-testing"


    def generate_self_signed_cert():
        """Generate a self-signed certificate for localhost."""
        if os.path.exists(CERT_FILE) and os.path.exists(KEY_FILE):
            return True

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
            return True
        except subprocess.CalledProcessError as e:
            print(f"Error generating certificate: {e.stderr.decode()}")
            return False


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


    def run_server():
        """Run the HTTPS server."""
        # Generate certificate if needed
        if not generate_self_signed_cert():
            sys.exit(1)

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
#endif
