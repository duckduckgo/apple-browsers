//
//  DBPDashboardNeedsYou.swift
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

#if DEBUG
import AppKit
import DataBrokerProtectionCore
import WebKit

/// Demo only: adds a Needs you section to the dashboard page and shows the agent's preview over the dashboard,
/// in this tab only, while a request started from it runs.
@MainActor
final class DBPDashboardNeedsYou: NSObject, WKScriptMessageHandlerWithReply {
    private static let handlerName = "pirDemo"

    private let agentInterface: DataBrokerProtectionAppToAgentInterface
    private let dataManager: DataBrokerProtectionDataManager?
    private weak var container: NSView?
    private var overlay: PreviewOverlayView?
    private var favicons: [String: String] = [:]
    private var faviconRequests: Set<String> = []
    private let faviconSession = URLSession(configuration: .ephemeral)

    init(agentInterface: DataBrokerProtectionAppToAgentInterface, dataManager: DataBrokerProtectionDataManaging?) {
        self.agentInterface = agentInterface
        self.dataManager = dataManager as? DataBrokerProtectionDataManager
        super.init()
    }

    /// Call before the web view is created from `configuration`.
    func install(in configuration: WKWebViewConfiguration) {
        let controller = configuration.userContentController
        controller.addUserScript(WKUserScript(source: Self.script, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
        controller.addScriptMessageHandler(self, contentWorld: .defaultClient, name: Self.handlerName)
    }

    func attach(to container: NSView) {
        self.container = container
        let interface = agentInterface
        let preview = DBPLivePreviewViewController(agentInterface: interface, hidesWhenIdle: false,
                                                   takeControl: { try await interface.takeControlOfLivePreview(operationID: $0) })
        let overlay = PreviewOverlayView(preview: preview)
        overlay.frame = container.bounds
        overlay.autoresizingMask = [.width, .height]
        overlay.clipsToBounds = true
        overlay.isHidden = true
        container.addSubview(overlay)
        self.overlay = overlay
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) async -> (Any?, String?) {
        guard let body = message.body as? [String: Any], let action = body["action"] as? String else { return (nil, "Unknown message") }
        switch action {
        case "list":
            return (needsYouJSON(), nil)
        case "start":
            guard let brokerId = (body["brokerId"] as? NSNumber)?.int64Value,
                  let profileQueryId = (body["profileQueryId"] as? NSNumber)?.int64Value,
                  let extractedProfileId = (body["extractedProfileId"] as? NSNumber)?.int64Value else { return (nil, "Missing ids") }
            overlay?.show(starting: body["brokerName"] as? String)
            do {
                try await agentInterface.startAssistedOptOut(brokerId: brokerId, profileQueryId: profileQueryId,
                                                             extractedProfileId: extractedProfileId, anchorFrame: screenFrame())
                return (true, nil)
            } catch {
                overlay?.hide()
                return (nil, error.localizedDescription)
            }
        default:
            return (nil, "Unknown action")
        }
    }

    private func needsYouJSON() -> [[String: Any]] {
        let pending = (try? dataManager?.assistedOptOuts()) ?? []
        // One row per broker and kind: a scan to run, or records to remove.
        var order: [String] = []
        var byRow: [String: [PIRAssistedOptOut]] = [:]
        for item in pending {
            let row = item.brokerURL + (item.extractedProfileId == nil ? "#scan" : "#opt-out")
            if byRow[row] == nil { order.append(row) }
            byRow[row, default: []].append(item)
        }
        return order.compactMap { row in
            guard let items = byRow[row], let first = items.first else { return nil }
            loadFavicon(for: first.brokerURL)
            return ["brokerName": first.brokerName, "brokerURL": first.brokerURL, "recordCount": items.count,
                    "isScan": first.extractedProfileId == nil, "favicon": favicons[first.brokerURL] ?? "",
                    "brokerId": first.brokerId, "profileQueryId": first.profileQueryId, "extractedProfileId": first.extractedProfileId ?? -1]
        }
    }

    /// Fetched natively and handed over as a data URL, since the dashboard page cannot load other sites' images.
    private func loadFavicon(for brokerURL: String) {
        guard favicons[brokerURL] == nil, !faviconRequests.contains(brokerURL),
              let url = URL(string: "https://icons.duckduckgo.com/ip3/\(brokerURL).ico") else { return }
        faviconRequests.insert(brokerURL)
        let session = faviconSession
        Task { @MainActor [weak self] in
            var request = URLRequest(url: url, timeoutInterval: 5)
            request.attribution = .user
            guard let (data, response) = try? await session.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let image = NSImage(data: data), let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
            self?.favicons[brokerURL] = "data:image/png;base64," + png.base64EncodedString()
        }
    }

    /// The dashboard's frame on screen, so the take-control window opens over it.
    private func screenFrame() -> CGRect? {
        guard let container, let window = container.window else { return nil }
        return window.convertToScreen(container.convert(container.bounds, to: nil))
    }

    // swiftlint:disable line_length
    /// The section from the assisted-removal design, rendered above the dashboard's site tabs.
    private static let script = """
    (() => {
      if (window.top !== window || window.__pirNeedsYou) return;
      window.__pirNeedsYou = true;
      const post = body => window.webkit.messageHandlers.\(handlerName).postMessage(body);
      const style = document.createElement('style');
      style.textContent = `
        #pir-needs-you { box-sizing: border-box; width: 100%; margin: 40px 0 32px; display: flex; flex-direction: column; align-items: center; gap: 24px; font-family: inherit; }
        #pir-needs-you[hidden] { display: none; }
        #pir-needs-you .head { display: flex; flex-direction: column; align-items: center; gap: 12px; text-align: center; }
        #pir-needs-you .pill { margin: 0; padding: 8px 14px 8px 16px; border-radius: 1000px; background: #ffd885; font-weight: 500; font-size: 14px; line-height: 16px; letter-spacing: 2px; text-transform: uppercase; color: rgba(26,11,3,.96); }
        #pir-needs-you .sub { margin: 0; font-size: 16px; line-height: 24px; color: rgba(0,0,0,.6); }
        #pir-needs-you ul { box-sizing: border-box; list-style: none; margin: 0; width: 100%; display: flex; flex-direction: column; gap: 16px; padding: 24px 24px 28px; border-radius: 32px; background: #fffbf0; box-shadow: 0 0 0 3px #ffd885, 0 1px 1.5px 3px rgba(0,0,0,.03); }
        #pir-needs-you .row { display: flex; align-items: center; gap: 16px; min-height: 52px; }
        #pir-needs-you .divider { height: 1px; background: rgba(0,0,0,.08); }
        #pir-needs-you .logo { width: 40px; height: 40px; flex: none; border-radius: 50%; background: #fff; object-fit: contain; }
        #pir-needs-you .text { flex: 1 1 0; min-width: 0; display: flex; flex-direction: column; }
        #pir-needs-you .name { font-size: 24px; line-height: 32px; color: rgba(26,11,3,.96); }
        #pir-needs-you .meta { font-size: 14px; line-height: 20px; color: rgba(26,11,3,.66); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
        #pir-needs-you button { flex: none; min-height: 48px; padding: 12px 28px; border: 0; border-radius: 999px; background: #ffeab8; color: #783b13; font: inherit; font-weight: 700; font-size: 16px; line-height: 16px; cursor: pointer; }
        #pir-needs-you button:hover { background: #ffdf94; }
        #pir-needs-you button:disabled { opacity: .6; cursor: default; }
      `;
      document.head.appendChild(style);
      const section = document.createElement('section');
      section.id = 'pir-needs-you';
      section.hidden = true;
      section.innerHTML = '<div class="head"><h2 class="pill">Needs you</h2><p class="sub"></p></div><ul></ul>';
      const list = section.querySelector('ul');
      const sub = section.querySelector('.sub');

      // As in the design: under the scan progress and stat cards, above the site tabs. Only on the dashboard
      // itself; onboarding and settings pages have no such slot.
      const place = () => {
        const stats = document.querySelector('[class*="scanProgressAndTopStats_grid"]');
        const tabs = document.querySelector('[class*="pirTabs_root"]');
        if (stats) {
          if (section.previousElementSibling !== stats) stats.after(section);
        } else if (tabs) {
          if (section.nextElementSibling !== tabs) tabs.before(section);
        } else {
          section.remove();
        }
      };

      let signature = '';
      const render = items => {
        const next = JSON.stringify(items);
        if (next === signature) return;
        signature = next;
        list.replaceChildren();
        items.forEach((item, index) => {
          if (index) list.appendChild(Object.assign(document.createElement('li'), { className: 'divider' }));
          const row = Object.assign(document.createElement('li'), { className: 'row' });
          const logo = Object.assign(document.createElement('img'), { className: 'logo', alt: '' });
          if (item.favicon) logo.src = item.favicon; else logo.style.visibility = 'hidden';
          const text = Object.assign(document.createElement('div'), { className: 'text' });
          const meta = item.isScan ? 'Search for your records \\u00b7 about 2 min with our help'
            : item.recordCount + (item.recordCount === 1 ? ' record' : ' records') + ' \\u00b7 about 1 min with our help';
          text.append(Object.assign(document.createElement('div'), { className: 'name', textContent: item.brokerName }),
                      Object.assign(document.createElement('div'), { className: 'meta', textContent: meta }));
          const button = Object.assign(document.createElement('button'), { type: 'button', textContent: item.isScan ? 'Start scan' : 'Start request' });
          button.onclick = async () => {
            button.disabled = true;
            try { await post({ action: 'start', ...item }); } catch (e) { button.disabled = false; }
          };
          row.append(logo, text, button);
          list.appendChild(row);
        });
        sub.textContent = items.some(item => item.isScan)
          ? 'These sites need a person to finish a search or a removal. We\\u2019ll do most of it.'
          : 'These sites need a person to finish the requests. We\\u2019ll do most of it.';
        section.hidden = items.length === 0;
      };

      const refresh = async () => {
        place();
        try { render(await post({ action: 'list' })); } catch (e) {}
      };
      refresh();
      setInterval(refresh, 3000);
    })();
    """
    // swiftlint:enable line_length
}

/// Dims the dashboard and floats the preview card over it, like the design's modal.
@MainActor
private final class PreviewOverlayView: NSView {
    private let preview: DBPLivePreviewViewController
    private let shadowHost = NSView()
    private var hideTask: Task<Void, Never>?

    init(preview: DBPLivePreviewViewController) {
        self.preview = preview
        super.init(frame: .zero)
        wantsLayer = true
        // The card clips to its rounded corners, so its shadow comes from a host view behind it.
        shadowHost.wantsLayer = true
        shadowHost.shadow = NSShadow()
        shadowHost.layer?.shadowColor = NSColor.black.cgColor
        shadowHost.layer?.shadowOpacity = 0.14
        shadowHost.layer?.shadowRadius = 30
        shadowHost.layer?.shadowOffset = CGSize(width: 0, height: -10)
        addSubview(shadowHost)
        let card = preview.view
        card.frame = shadowHost.bounds
        card.autoresizingMask = [.width, .height]
        shadowHost.addSubview(card)
        preview.activityChanged = { [weak self] isActive in self?.previewActivityChanged(isActive) }
        preview.userControlChanged = { [weak self] isUserControlling in self?.userControlChanged(isUserControlling) }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.4).cgColor
    }

    // Sized by frame, not constraints, so the card never limits how small or large the window can get.
    // As in the design: fill the dashboard with a 32pt margin, up to the design's size.
    override func layout() {
        super.layout()
        let maximum = DBPLivePreviewViewController.maximumSize
        let size = CGSize(width: max(0, min(maximum.width, bounds.width - 64)), height: max(0, min(maximum.height, bounds.height - 64)))
        shadowHost.frame = CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
                                  width: size.width, height: size.height).integral
    }

    // The scrim takes every click so the dashboard behind it stays inert, like a modal.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0 else { return nil }
        return super.hitTest(point) ?? self
    }

    override func mouseDown(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}

    func show(starting brokerName: String?) {
        hideTask?.cancel()
        alphaValue = 1
        isHidden = false
        preview.showStarting(brokerName: brokerName)
    }

    func hide() {
        hideTask?.cancel()
        isHidden = true
    }

    // While the user helps in the page's own window, step out of the way; come back when the agent resumes.
    // Fading keeps the preview polling, which hiding would stop, so it still notices the resume.
    private func userControlChanged(_ isUserControlling: Bool) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            animator().alphaValue = isUserControlling ? 0 : 1
        }
    }

    private func previewActivityChanged(_ isActive: Bool) {
        hideTask?.cancel()
        guard !isActive else { return }
        // Let the finished state read for a moment, then give the dashboard back.
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            self?.isHidden = true
        }
    }
}
#endif
