//
//  Tab+UIDelegate.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

import Combine
import Common
import CommonObjCExtensions
import DDGNavigation
import Foundation
import FoundationExtensions
import PDFKit
import PixelKit
import UniformTypeIdentifiers
import WebKit

extension Tab: WKUIDelegate {

    // "protected" delegate property
    private var delegate: TabDelegate? {
        self.value(forKey: Tab.objcDelegateKeyPath) as? TabDelegate
    }

    @MainActor private static var expectedSaveDataToFileCallback: (@MainActor (URL?) -> Void)?
    @MainActor
    private static func consumeExpectedSaveDataToFileCallback() -> (@MainActor (URL?) -> Void)? {
        defer {
            expectedSaveDataToFileCallback = nil
        }
        return expectedSaveDataToFileCallback
    }

    @objc(_webView:saveDataToFile:suggestedFilename:mimeType:originatingURL:)
    func webView(_ webView: WKWebView, saveDataToFile data: Data, suggestedFilename: String, mimeType: String, originatingURL: URL) {
        Task {
            var result: URL?
            do {
                result = try await saveDownloadedData(data, suggestedFilename: suggestedFilename, mimeType: mimeType, originatingURL: originatingURL)
            } catch {
                assertionFailure("Save web content failed with \(error)")
            }
            // when print function saves a PDF setting the callback, return the saved temporary file to it
            await Self.consumeExpectedSaveDataToFileCallback()?(result)
        }
    }

    @MainActor
    @objc(_webView:createWebViewWithConfiguration:forNavigationAction:windowFeatures:completionHandler:)
    func webView(_ webView: WKWebView,
                 createWebViewWithConfiguration configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures,
                 completionHandler: @escaping (WKWebView?) -> Void) {

        guard isCreateWebViewGatingFailsafeEnabled else {
            completionHandler(self.popupHandling?.createWebView(from: webView,
                                                                with: configuration,
                                                                for: navigationAction,
                                                                windowFeatures: windowFeatures))
            return
        }

        // Defer createWebView handling until any in-flight `decidePolicyForNavigationAction` responder-chain work completes.
        // This prevents a race condition where the createWebView callback for a pop-up is called before a PopupHandlingTabExtension decision
        // to open a pop-up is made.
        // https://app.asana.com/1/137249556945/project/1202406491309510/task/1212353379833164?focus=true
        dispatchCreateWebView { [weak self] in
            completionHandler(self?.popupHandling?.createWebView(from: webView,
                                                                 with: configuration,
                                                                 for: navigationAction,
                                                                 windowFeatures: windowFeatures))
        }
    }

    @MainActor
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        self.popupHandling?.createWebView(from: webView, with: configuration, for: navigationAction, windowFeatures: windowFeatures)
    }

    /// Called by WebKit to get the website's camera / microphone decision, see how getUserMedia works below.
    ///
    /// How WebKit (macOS 13+) handles getUserMedia before it reaches requestMediaCapturePermissionFor:
    /// 1. `queryPermission` is called for both "camera" and "microphone" to get the website's stored state.
    /// 2. `requestSystemValidation` reads `AVCaptureDevice.authorizationStatus(for:)` for each requested media type:
    ///    `.denied`/`.restricted` rejects the request without calling any other delegate method,
    ///    `.notDetermined` shows the macOS prompt before ours.
    /// 3. Only then `requestMediaCapturePermissionFor:` is called.
    /// With websitePermissionsPrompts on, to show our prompt first (with its System Settings step for denied access),
    /// step 1 sets a one-shot token making step 2 read `.authorized` (see AVCaptureDevice+SwizzledAuthState.swift),
    /// step 3 drops this tab's tokens that weren't used.
    /// `queryPermission` is also called for navigator.permissions.query and enumerateDevices, which skip steps 2-3:
    /// those tokens are dropped on the next request or when they expire.
    /// https://github.com/WebKit/WebKit/blob/99051d5d08cd9f19ec76ce599f7539d070b1ae09/Source/WebKit/UIProcess/UserMediaPermissionRequestManagerProxy.cpp#L620
    /// https://github.com/WebKit/WebKit/blob/99051d5d08cd9f19ec76ce599f7539d070b1ae09/Source/WebKit/UIProcess/Cocoa/UserMediaPermissionRequestManagerProxy.mm#L158
    @MainActor
    @available(macOS 13.0, *)
    @objc(_webView:queryPermission:forOrigin:completionHandler:)
    func webView(_ webView: WKWebView,
                 queryPermission name: String,
                 forOrigin origin: WKSecurityOrigin,
                 completionHandler: @escaping (WKPermissionDecision) -> Void) {
        permissions.queryMediaPermission(name)
        // Always `.prompt`: the actual decision (stored website decision + macOS status) is made in step 3, which
        // WebKit calls regardless of this answer. `.grant` would mark the origin as having persistent access and
        // reveal device labels/IDs to enumerateDevices before we've decided, `.deny` would hide the devices,
        // and both would be reported to the page by navigator.permissions.query.
        // https://github.com/WebKit/WebKit/blob/99051d5d08cd9f19ec76ce599f7539d070b1ae09/Source/WebKit/UIProcess/UserMediaPermissionRequestManagerProxy.cpp#L993
        completionHandler(.prompt)
    }

    /// macOS 12: called instead of `queryPermission` step 1 above, without telling the requested media type.
    /// It only observes step 2 to reflect a macOS denial in the address bar: website permission prompts need macOS 13+.
    @available(macOS, deprecated: 13.0, message: "Not called since macOS 13, WebKit calls _webView:queryPermission:forOrigin:completionHandler: instead. Remove with macOS 12 support.")
    @MainActor
    @objc(_webView:checkUserMediaPermissionForURL:mainFrameURL:frameIdentifier:decisionHandler:)
    func webView(_ webView: WKWebView,
                 checkUserMediaPermissionFor url: NSURL?,
                 mainFrameURL: NSURL?,
                 frameIdentifier: UInt64,
                 decisionHandler: @escaping (String, Bool) -> Void) {
        self.permissions.checkUserMediaPermission(for: url as? URL, mainFrameURL: mainFrameURL as? URL, decisionHandler: decisionHandler)
    }

    /// Asks for camera and/or microphone access (getUserMedia), step 3 of the flow described at `queryPermission`.
    /// Decided by `PermissionModel.permissions(_:requestedForDomain:)` for the top-level website: saved decision, prompt, macOS status.
    /// https://github.com/WebKit/WebKit/blob/995f6b1595611c934e742a4f3a9af2e678bc6b8d/Source/WebKit/UIProcess/API/Cocoa/WKUIDelegate.h#L147
    @objc(webView:requestMediaCapturePermissionForOrigin:initiatedByFrame:type:decisionHandler:)
    func webView(_ webView: WKWebView,
                 requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo,
                 type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        guard let permissions = [PermissionType](devices: type) else {
            assertionFailure("Could not decode PermissionType")
            decisionHandler(.deny)
            return
        }

        self.permissions.permissions(permissions, requestedForDomain: origin.host, decisionHandler: decisionHandler)
    }

    /// Legacy variant of `requestMediaCapturePermissionFor:`: WebKit only calls it when that one isn't implemented.
    /// Decided for the requesting frame's host; an unknown device set or host is denied.
    /// https://github.com/WebKit/WebKit/blob/9d7278159234e0bfa3d27909a19e695928f3b31e/Source/WebKit/UIProcess/API/Cocoa/WKUIDelegatePrivate.h#L126
    @objc(_webView:requestUserMediaAuthorizationForDevices:url:mainFrameURL:decisionHandler:)
    func webView(_ webView: WKWebView,
                 requestUserMediaAuthorizationFor devices: UInt,
                 url: URL,
                 mainFrameURL: URL,
                 decisionHandler: @escaping (Bool) -> Void) {
        let devices = _WKCaptureDevices(rawValue: devices)
        guard let permissions = [PermissionType](devices: devices),
              let host = url.isFileURL ? .localhost : url.host,
              !host.isEmpty else {
            decisionHandler(false)
            return
        }

        self.permissions.permissions(permissions, requestedForDomain: host, decisionHandler: decisionHandler)
    }

    /// Camera or microphone capture started, stopped or was muted: updates the address bar permission states.
    @objc(_webView:mediaCaptureStateDidChange:)
    func webView(_ webView: WKWebView, mediaCaptureStateDidChange state: UInt /*_WKMediaCaptureStateDeprecated*/) {
        self.permissions.mediaCaptureStateDidChange()
    }

    /// Legacy location request: WebKit only calls it when the origin-based variant below isn't implemented.
    /// Decided for the requesting frame's host.
    /// https://github.com/WebKit/WebKit/blob/9d7278159234e0bfa3d27909a19e695928f3b31e/Source/WebKit/UIProcess/API/Cocoa/WKUIDelegatePrivate.h#L131
    @objc(_webView:requestGeolocationPermissionForFrame:decisionHandler:)
    func webView(_ webView: WKWebView, requestGeolocationPermissionFor frame: WKFrameInfo, decisionHandler: @escaping (Bool) -> Void) {
        let url = frame.safeRequest?.url ?? .empty
        let host = url.isFileURL ? .localhost : (url.host ?? "")
        self.permissions.permissions(.geolocation, requestedForDomain: host, decisionHandler: decisionHandler)
    }

    /// Asks for location access (navigator.geolocation), decided for the requesting frame's host.
    /// https://github.com/WebKit/WebKit/blob/9d7278159234e0bfa3d27909a19e695928f3b31e/Source/WebKit/UIProcess/API/Cocoa/WKUIDelegatePrivate.h#L132
    @objc(_webView:requestGeolocationPermissionForOrigin:initiatedByFrame:decisionHandler:)

    func webView(_ webView: WKWebView,
                 requestGeolocationPermissionFor origin: WKSecurityOrigin,
                 initiatedBy frame: WKFrameInfo,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        let url = frame.safeRequest?.url ?? .empty
        let host = url.isFileURL ? .localhost : (url.host ?? "")
        self.permissions.permissions(.geolocation, requestedForDomain: host) { granted in
            decisionHandler(granted ? .grant : .deny)
        }
    }

    @objc(_webView:requestStorageAccessPanelForDomain:underCurrentDomain:completionHandler:)
    @available(macOS 10.14, iOS 12.0, *)
    func webView(_ webView: WKWebView,
                 requestStorageAccessPanelForDomain requestingDomain: String,
                 underCurrentDomain currentDomain: String,
                 completionHandler: @escaping (Bool) -> Void) {
        let alert = NSAlert.storageAccessAlert(currentDomain: currentDomain,
                                               requestingDomain: requestingDomain)
        let response = alert.runModal()
        completionHandler(response == .alertFirstButtonReturn)
    }

    @objc(_webView:requestStorageAccessPanelForDomain:underCurrentDomain:forQuirkDomains:completionHandler:)
    @available(macOS 15.0, iOS 18.0, visionOS 2.0, *)
    func webView(_ webView: WKWebView,
                 requestStorageAccessPanelForDomain requestingDomain: String,
                 underCurrentDomain currentDomain: String,
                 forQuirkDomains quirkDomains: [String: [String]],
                 completionHandler: @escaping (Bool) -> Void) {
        let alert = NSAlert.storageAccessAlertForQuirkDomains(requestingDomain: requestingDomain,
                                                              currentDomain: currentDomain,
                                                              quirkDomains: Array(quirkDomains.keys))
        let response = alert.runModal()
        completionHandler(response == .alertFirstButtonReturn)
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let dialog = UserDialogType.openPanel(.init(parameters) { result in
            completionHandler(try? result.get())
        })
        let url = frame.safeRequest?.url ?? .empty
        let host = url.isFileURL ? .localhost : (url.host ?? "")
        userInteractionDialog = UserDialog(sender: .page(domain: host), dialog: dialog)
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        createAlertDialog(initiatedByFrame: frame, prompt: message) { parameters in
            .alert(.init(parameters, callback: { result in
                switch result {
                case .failure:
                    completionHandler()
                case .success:
                    completionHandler()
                }
            }))
        }
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (Bool) -> Void) {
        createAlertDialog(initiatedByFrame: frame, prompt: message) { parameters in
            .confirm(.init(parameters, callback: { result in
                switch result {
                case .failure:
                    completionHandler(false)
                case .success(let alertResult):
                    completionHandler(alertResult)
                }
            }))
        }
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        createAlertDialog(initiatedByFrame: frame, prompt: prompt, defaultInputText: defaultText) { parameters in
            .textInput(.init(parameters, callback: { result in
                switch result {
                case .failure:
                    completionHandler(nil)
                case .success(let alertResult):
                    completionHandler(alertResult)
                }
            }))
        }
    }

    private func createAlertDialog(initiatedByFrame frame: WKFrameInfo, prompt: String, defaultInputText: String? = nil, queryCreator: (JSAlertParameters) -> JSAlertQuery) {
        let url = frame.safeRequest?.url
        // in case the web view is navigating to another host
        ?? webView.backForwardList.currentItem?.url
        ?? self.url
        ?? .empty
        let host = url.isFileURL ? .localhost : (url.host ?? "")

        let parameters = JSAlertParameters(
            domain: host,
            prompt: prompt,
            defaultInputText: defaultInputText
        )
        let alertQuery = queryCreator(parameters)
        let dialog = UserDialogType.jsDialog(alertQuery)
        userInteractionDialog = UserDialog(sender: .page(domain: host), dialog: dialog)
    }

    func webViewDidClose(_ webView: WKWebView) {
        delegate?.closeTab(self)
    }

    func runPrintOperation(for frameHandle: FrameHandle?, in webView: WKWebView, completionHandler: ((Bool) -> Void)? = nil) {
        guard let printOperation = webView.printOperation(for: frameHandle) else { return }

        if printOperation.view?.frame.isEmpty == true {
            printOperation.view?.frame = webView.bounds
        }

        runPrintOperation(printOperation, completionHandler: completionHandler)
    }

    func runPrintOperation(_ printOperation: NSPrintOperation, completionHandler: ((Bool) -> Void)? = nil) {
        let dialog = UserDialogType.print(.init(printOperation) { result in
            completionHandler?((try? result.get()) ?? false)
        })
        userInteractionDialog = UserDialog(sender: .user, dialog: dialog)
    }

    @objc(_webView:printFrame:)
    func webView(_ webView: WKWebView, printFrame frameHandle: FrameHandle?) {
        self.runPrintOperation(for: frameHandle, in: webView)
    }

    @objc(_webView:printFrame:pdfFirstPageSize:completionHandler:)
    func webView(_ webView: WKWebView, printFrame frameHandle: FrameHandle?, pdfFirstPageSize size: CGSize, completionHandler: @escaping () -> Void) {
        self.runPrintOperation(for: frameHandle, in: webView) { _ in completionHandler() }
    }

    @preconcurrency @MainActor
    func print(pdfHUD: WKPDFHUDViewWrapper? = nil) {
        if let pdfHUD {
            Self.expectedSaveDataToFileCallback = { [weak self] url in
                guard let self, let url,
                      let pdfDocument = PDFDocument(url: url) else {
                    assertionFailure("Could not load PDF document from \(url?.path ?? "<nil>")")
                    return
                }
                // Set up NSPrintOperation
                guard let printOperation = pdfDocument.printOperation(for: .shared, scalingMode: .pageScaleNone, autoRotate: false) else {
                    assertionFailure("Could not print PDF document")
                    return
                }

                self.runPrintOperation(printOperation) { _ in
                    try? FileManager.default.removeItem(at: url)
                }
            }
            saveWebContent(pdfHUD: pdfHUD, location: .temporary)
            return
        }

        self.runPrintOperation(for: nil, in: self.webView)
    }

    @objc(_webView:hasVideoInPictureInPictureDidChange:)
    func webView(_ webView: WKWebView, hasVideoInPictureInPictureDidChange hasVideoInPictureInPicture: Bool) {
        self.tabSuspension?.hasVideoInPictureInPicture = hasVideoInPictureInPicture
        if hasVideoInPictureInPicture {
            // Fire pixel when Picture-in-Picture is activated
            PixelKit.fire(GeneralPixel.pictureInPictureVideoPlayback, frequency: .dailyAndCount)
        }
    }
}

extension Tab: WKInspectorDelegate {
    @MainActor
    func inspector(_ inspector: NSObject, openURLExternally url: NSURL?) {
        let tab = Tab(content: url.map { Tab.Content.url($0 as URL, source: .link) } ?? .none,
                      burnerMode: BurnerMode(isBurner: burnerMode.isBurner),
                      webViewSize: webView.superview?.bounds.size ?? .zero)
        delegate?.tab(self, createdChild: tab, of: .window(active: true, burner: burnerMode.isBurner))
    }

    // Private WebKit delegate method to detect when developer tools inspector is attached
    @objc(_webView:didAttachLocalInspector:)
    func webView(_ webView: WKWebView, didAttachLocalInspector inspector: NSObject) {
        // Fire pixel when developer tools are opened
        PixelKit.fire(GeneralPixel.developerToolsOpened, frequency: .dailyAndCount)
    }
}
