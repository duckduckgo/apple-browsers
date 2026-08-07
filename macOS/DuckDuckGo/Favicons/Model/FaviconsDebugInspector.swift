//
//  FaviconsDebugInspector.swift
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

import AppKit
import AppKitExtensions
import Foundation
import WebKit

/// Serves the debug-only Favicons inspector page at `duck://favicons` (Debug ▸ Inspect Favicons).
///
/// The page is a self-contained in-app HTML/JS app plus a JSON/PNG API, so it ships without the
/// content-scope-scripts bundle pipeline. `DuckURLSchemeHandler` routes `duck://favicons` requests here.
/// All access goes through `FaviconManagementDebugging` — the in-app favicon stack, which holds the
/// decryption key — so the encrypted URL/image columns are handled transparently.
///
/// Static assets (the page HTML and its script) are returned synchronously; the `/api/` endpoints
/// complete asynchronously, and in-flight tasks are tracked so a task WebKit stops mid-await isn't messaged.
/// Mutations use GET with query params on purpose: `WKURLSchemeHandler` doesn't reliably receive the
/// HTTP body of a POST, so request data is carried in the URL.
final class FaviconsDebugInspector {

    private let faviconManager: FaviconManagement

    /// In-flight API tasks that complete after an await; used to skip messaging a task WebKit has stopped.
    private var runningTasks = Set<ObjectIdentifier>()

    init(faviconManager: FaviconManagement) {
        self.faviconManager = faviconManager
    }

    func handle(requestURL: URL, urlSchemeTask: WKURLSchemeTask) {
        switch requestURL.path {
        case "", "/", "/index.html":
            send(Page.html.utf8data, mimeType: "text/html", for: requestURL, to: urlSchemeTask)
            return
        case "/app.js":
            send(Page.js.utf8data, mimeType: "text/javascript", for: requestURL, to: urlSchemeTask)
            return
        default:
            break
        }

        guard requestURL.path.hasPrefix("/api/"), let debug = faviconManager as? FaviconManagementDebugging else {
            fail(urlSchemeTask, statusCode: 404, for: requestURL)
            return
        }

        let taskID = ObjectIdentifier(urlSchemeTask)
        runningTasks.insert(taskID)
        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await Self.apiResponse(for: requestURL, debug: debug)
            // The task may have been stopped while awaiting; `remove` returns nil if so.
            guard self.runningTasks.remove(taskID) != nil else { return }
            switch result {
            case .data(let data, let mimeType):
                self.send(data, mimeType: mimeType, for: requestURL, to: urlSchemeTask)
            case .notFound:
                self.fail(urlSchemeTask, statusCode: 404, for: requestURL)
            }
        }
    }

    /// Called when WebKit stops a scheme task, so a pending async completion is skipped instead of
    /// messaging a stopped task (which would crash).
    func webViewDidStop(_ urlSchemeTask: WKURLSchemeTask) {
        runningTasks.remove(ObjectIdentifier(urlSchemeTask))
    }

    // MARK: - Responses

    private func send(_ data: Data, mimeType: String, for url: URL, to task: WKURLSchemeTask) {
        // Respond with HTTP 200 (not a bare URLResponse) so the page's `fetch()` sees `response.ok`.
        // The lazy image loader relies on `ok` to tell a served favicon apart from a 404.
        let headers = ["Content-Type": mimeType, "Content-Length": String(data.count)]
        guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers) else {
            task.didFailWithError(URLError(.badServerResponse))
            return
        }
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    private func fail(_ task: WKURLSchemeTask, statusCode: Int, for url: URL) {
        guard let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: nil) else {
            task.didFailWithError(URLError(.badServerResponse))
            return
        }
        task.didReceive(response)
        task.didReceive(Data())
        task.didFinish()
    }

    @MainActor
    private static func apiResponse(for requestURL: URL, debug: FaviconManagementDebugging) async -> Response {
        let queryItems = URLComponents(url: requestURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func queryValue(_ name: String) -> String? { queryItems.first { $0.name == name }?.value }

        switch requestURL.path {
        case "/api/list":
            let items = await debug.allFaviconsMetadata().map(Item.init(metadata:))
            guard let data = try? JSONEncoder().encode(items) else { return .notFound }
            return .data(data, "application/json")

        case "/api/image":
            guard let idString = queryValue("id"), let id = UUID(uuidString: idString),
                  let image = await debug.faviconImage(withIdentifier: id), let png = image.pngData() else {
                return .notFound
            }
            return .data(png, "image/png")

        case "/api/delete":
            let ids = (queryValue("ids") ?? "").split(separator: ",").compactMap { UUID(uuidString: String($0)) }
            await debug.deleteFavicons(withIdentifiers: Set(ids))
            return jsonCount(ids.count)

        case "/api/deleteAll":
            let count = await debug.allFaviconsMetadata().count
            await debug.deleteAllFavicons()
            return jsonCount(count)

        default:
            return .notFound
        }
    }

    private static func jsonCount(_ count: Int) -> Response {
        guard let data = try? JSONEncoder().encode(["deleted": count]) else { return .notFound }
        return .data(data, "application/json")
    }
}

private enum Response {
    case data(Data, String)
    case notFound
}

/// JSON row shape consumed by the inspector page's script.
private struct Item: Encodable {
    let id: String
    let faviconURL: String
    let documentURL: String
    let host: String
    let relation: Int
    let dateCreated: Double

    init(metadata: FaviconMetadata) {
        id = metadata.identifier.uuidString
        faviconURL = metadata.url.absoluteString
        documentURL = metadata.documentUrl.absoluteString
        host = metadata.documentUrl.host ?? metadata.url.host ?? ""
        relation = metadata.relation.rawValue
        dateCreated = metadata.dateCreated.timeIntervalSince1970
    }
}

/// Self-contained HTML + JS for the debug Favicons inspector. The script is served separately as `/app.js`.
private enum Page {

    static let html = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Favicons</title>
    <style>
    :root { color-scheme: light dark; }
    body { font: 13px -apple-system, system-ui, sans-serif; margin: 0; padding: 0 16px 24px; }
    h1 { font-size: 18px; margin: 0 0 8px; }
    header { position: sticky; top: 0; background: Canvas; padding-top: 12px; z-index: 2; }
    .toolbar { display: flex; gap: 8px; align-items: center; margin-bottom: 8px; flex-wrap: wrap; }
    #search { flex: 1; min-width: 200px; padding: 4px 8px; }
    #count { color: GrayText; white-space: nowrap; }
    button { padding: 4px 10px; }
    button.danger { color: #fff; background: #c0392b; border: 0; border-radius: 4px; }
    button:disabled { opacity: 0.5; }
    button.copy { padding: 1px 6px; font-size: 11px; }
    /* Single table so the header row shares column widths with the body. */
    table { width: 100%; border-collapse: collapse; table-layout: auto; }
    th, td { text-align: left; padding: 4px 6px; border-bottom: 1px solid rgba(128,128,128,0.25); vertical-align: top; }
    thead th { position: sticky; top: var(--header-h, 0px); background: Canvas; z-index: 1; }
    .sortable { cursor: pointer; user-select: none; }
    .sortable:hover { text-decoration: underline; }
    td.host { max-width: 130px; overflow-wrap: anywhere; }
    td.url { max-width: 360px; }
    .urlwrap { display: flex; gap: 6px; align-items: flex-start; min-width: 0; }
    .urltext { flex: 1 1 auto; min-width: 0; overflow-wrap: anywhere; font-family: ui-monospace, monospace; font-size: 11px; }
    .copy { flex: 0 0 auto; }
    td.size { white-space: nowrap; color: GrayText; font-variant-numeric: tabular-nums; }
    img.fav { width: 16px; height: 16px; object-fit: contain; background: rgba(128,128,128,0.15); }
    </style>
    </head>
    <body>
    <header>
    <h1>Favicons</h1>
    <div class="toolbar">
    <input id="search" type="search" placeholder="Filter by host or URL" autocomplete="off">
    <span id="count"></span>
    <button id="reload">Reload</button>
    <button id="deleteSelected" disabled>Delete selected</button>
    <button id="deleteAll" class="danger">Delete all</button>
    </div>
    </header>
    <table>
    <thead><tr>
    <th><input type="checkbox" id="selectAll"></th>
    <th>Icon</th>
    <th class="sortable" data-sort="host">Host</th>
    <th>Favicon URL</th>
    <th>Document URL</th>
    <th>Size (<span class="sortable" data-sort="px">px</span> / <span class="sortable" data-sort="bytes">B</span>)</th>
    <th class="sortable" data-sort="rel">Rel</th>
    <th>Created</th>
    </tr></thead>
    <tbody id="rows"></tbody>
    </table>
    <script src="/app.js"></script>
    </body>
    </html>
    """

    static let js = """
    "use strict";
    var state = { items: [], filter: "", sizes: {}, sort: { key: "created", dir: -1 } };
    var relName = { "0": "other", "1": "icon", "2": "favicon" };
    var loadingAllSizes = false;

    function el(tag, text) {
      var e = document.createElement(tag);
      if (text !== undefined) { e.textContent = text; }
      return e;
    }

    function humanBytes(n) {
      if (n < 1024) { return n + " B"; }
      if (n < 1048576) { return (n / 1024).toFixed(1) + " kB"; }
      return (n / 1048576).toFixed(1) + " MB";
    }

    // Copy with a fallback for environments where navigator.clipboard is unavailable on the duck:// page.
    function fallbackCopy(text) {
      var ta = document.createElement("textarea");
      ta.value = text;
      ta.style.position = "fixed";
      ta.style.opacity = "0";
      document.body.appendChild(ta);
      ta.focus();
      ta.select();
      try { document.execCommand("copy"); } catch (e) {}
      document.body.removeChild(ta);
    }

    function copyToClipboard(text, btn) {
      var restore = function() {
        btn.textContent = "Copied";
        setTimeout(function() { btn.textContent = "Copy"; }, 1000);
      };
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(restore, function() { fallbackCopy(text); restore(); });
      } else {
        fallbackCopy(text);
        restore();
      }
    }

    // Favicon images and their sizes load lazily as rows scroll into view. The row's own <img> both
    // displays the favicon and yields its pixel dimensions on load; blob.size gives the byte size.
    // Measured sizes are cached in state.sizes[id] so sorting by size can use them.
    var imageObserver = new IntersectionObserver(function(entries) {
      entries.forEach(function(entry) {
        if (!entry.isIntersecting) { return; }
        imageObserver.unobserve(entry.target);
        if (entry.target.__loadFavicon) { entry.target.__loadFavicon(); }
      });
    }, { rootMargin: "300px" });

    function lazyLoadFavicon(img, sizeCell, id) {
      img.__loadFavicon = function() {
        fetch("/api/image?id=" + encodeURIComponent(id)).then(function(r) {
          if (!r.ok) { throw new Error("missing"); }
          return r.blob();
        }).then(function(blob) {
          var bytes = blob.size;
          var url = URL.createObjectURL(blob);
          img.onload = function() {
            URL.revokeObjectURL(url);
            state.sizes[id] = { w: img.naturalWidth, h: img.naturalHeight, px: img.naturalWidth * img.naturalHeight, bytes: bytes };
            sizeCell.textContent = img.naturalWidth + "×" + img.naturalHeight + " · " + humanBytes(bytes);
          };
          img.onerror = function() {
            URL.revokeObjectURL(url);
            state.sizes[id] = { w: 0, h: 0, px: -1, bytes: -1 };
            sizeCell.textContent = "—";
          };
          img.src = url;
        }).catch(function() {
          state.sizes[id] = { w: 0, h: 0, px: -1, bytes: -1 };
          sizeCell.textContent = "—";
        });
      };
      imageObserver.observe(img);
    }

    // Measures one favicon (without displaying it) by decoding a detached image; records state.sizes[id].
    function measureFavicon(id) {
      return fetch("/api/image?id=" + encodeURIComponent(id)).then(function(r) {
        if (!r.ok) { throw new Error("missing"); }
        return r.blob();
      }).then(function(blob) {
        var bytes = blob.size;
        return new Promise(function(resolve, reject) {
          var url = URL.createObjectURL(blob);
          var im = new Image();
          im.onload = function() {
            state.sizes[id] = { w: im.naturalWidth, h: im.naturalHeight, px: im.naturalWidth * im.naturalHeight, bytes: bytes };
            URL.revokeObjectURL(url);
            resolve();
          };
          im.onerror = function() { URL.revokeObjectURL(url); reject(new Error("decode")); };
          im.src = url;
        });
      }).catch(function(err) {
        state.sizes[id] = { w: 0, h: 0, px: -1, bytes: -1 };
        throw err;
      });
    }

    // Sorting by size needs every favicon measured. Fetch the not-yet-seen ones (bounded concurrency),
    // updating a progress count, then re-render. Misses are recorded with -1 so they sort last.
    function ensureAllSizesLoaded() {
      if (loadingAllSizes) { return; }
      var missing = state.items.filter(function(i) { return !state.sizes[i.id]; });
      if (!missing.length) { return; }
      loadingAllSizes = true;
      var idx = 0, active = 0, completed = 0, total = missing.length;
      function step() {
        if (idx >= total && active === 0) {
          loadingAllSizes = false;
          render();
          return;
        }
        while (active < 12 && idx < total) {
          var id = missing[idx++].id;
          active++;
          measureFavicon(id).then(function() {}, function() {}).then(function() {
            active--; completed++;
            setCount(" · measuring " + completed + "/" + total);
            step();
          });
        }
      }
      step();
    }

    function urlCell(text, withCopy) {
      var td = el("td");
      td.className = "url";
      var wrap = el("div");
      wrap.className = "urlwrap";
      var span = el("span", text);
      span.className = "urltext";
      span.title = text;
      wrap.appendChild(span);
      if (withCopy) {
        var btn = el("button", "Copy");
        btn.className = "copy";
        btn.addEventListener("click", function() { copyToClipboard(text, btn); });
        wrap.appendChild(btn);
      }
      td.appendChild(wrap);
      return td;
    }

    function syncHeaderOffset() {
      var header = document.querySelector("header");
      if (header) { document.documentElement.style.setProperty("--header-h", header.offsetHeight + "px"); }
    }

    function metric(id, field) {
      var s = state.sizes[id];
      return s ? s[field] : -1;
    }

    function cmp(a, b) { return a < b ? -1 : a > b ? 1 : 0; }

    function sortItems(items) {
      var k = state.sort.key, d = state.sort.dir;
      var arr = items.slice();
      arr.sort(function(a, b) {
        var r;
        if (k === "host") { r = a.host.localeCompare(b.host); }
        else if (k === "rel") { r = cmp(a.relation, b.relation); }
        else if (k === "px") { r = cmp(metric(a.id, "px"), metric(b.id, "px")); }
        else if (k === "bytes") { r = cmp(metric(a.id, "bytes"), metric(b.id, "bytes")); }
        else { r = cmp(a.dateCreated, b.dateCreated); }
        if (r === 0) { r = cmp(a.dateCreated, b.dateCreated); }
        return d * r;
      });
      return arr;
    }

    function filtered() {
      var f = state.filter.trim().toLowerCase();
      var items = !f ? state.items : state.items.filter(function(i) {
        return (i.host + " " + i.faviconURL + " " + i.documentURL).toLowerCase().indexOf(f) !== -1;
      });
      return sortItems(items);
    }

    function setSort(key) {
      if (state.sort.key === key) {
        state.sort.dir = -state.sort.dir;
      } else {
        var descFirst = (key === "px" || key === "bytes" || key === "created");
        state.sort = { key: key, dir: descFirst ? -1 : 1 };
      }
      if (key === "px" || key === "bytes") { ensureAllSizesLoaded(); }
      render();
    }

    function updateSortHeaders() {
      var els = document.querySelectorAll("[data-sort]");
      Array.prototype.forEach.call(els, function(e) {
        var base = e.getAttribute("data-label");
        if (base === null) { base = e.textContent; e.setAttribute("data-label", base); }
        var active = state.sort.key === e.getAttribute("data-sort");
        e.textContent = base + (active ? (state.sort.dir > 0 ? " ▲" : " ▼") : "");
      });
    }

    function setCount(suffix) {
      var n = (state.filter.trim() ? filtered().length : state.items.length);
      document.getElementById("count").textContent = n + " / " + state.items.length + " favicons" + (suffix || "");
    }

    function selectedIds() {
      var boxes = document.querySelectorAll("tbody input[type=checkbox]:checked");
      return Array.prototype.map.call(boxes, function(b) { return b.getAttribute("data-id"); });
    }

    function updateButtons() {
      var n = selectedIds().length;
      var btn = document.getElementById("deleteSelected");
      btn.disabled = n === 0;
      btn.textContent = n > 0 ? ("Delete selected (" + n + ")") : "Delete selected";
    }

    function render() {
      var items = filtered();
      setCount("");
      updateSortHeaders();
      var rows = document.getElementById("rows");
      imageObserver.disconnect();
      rows.textContent = "";
      items.forEach(function(i) {
        var tr = document.createElement("tr");

        var cbCell = el("td");
        var box = document.createElement("input");
        box.type = "checkbox";
        box.setAttribute("data-id", i.id);
        box.addEventListener("change", updateButtons);
        cbCell.appendChild(box);
        tr.appendChild(cbCell);

        var iconCell = el("td");
        var img = document.createElement("img");
        img.className = "fav";
        iconCell.appendChild(img);
        tr.appendChild(iconCell);

        var hostCell = el("td", i.host);
        hostCell.className = "host";
        tr.appendChild(hostCell);

        tr.appendChild(urlCell(i.faviconURL, true));
        tr.appendChild(urlCell(i.documentURL, true));

        var sizeCell = el("td");
        sizeCell.className = "size";
        var known = state.sizes[i.id];
        if (known && known.px >= 0) {
          sizeCell.textContent = known.w + "×" + known.h + " · " + humanBytes(known.bytes);
        } else {
          sizeCell.textContent = known ? "—" : "…";
        }
        tr.appendChild(sizeCell);

        tr.appendChild(el("td", relName[String(i.relation)] || String(i.relation)));

        var created = "";
        try { created = new Date(i.dateCreated * 1000).toISOString().slice(0, 10); } catch (e) { created = ""; }
        tr.appendChild(el("td", created));

        rows.appendChild(tr);
        lazyLoadFavicon(img, sizeCell, i.id);
      });
      var selectAll = document.getElementById("selectAll");
      if (selectAll) { selectAll.checked = false; }
      updateButtons();
    }

    function load() {
      fetch("/api/list").then(function(r) { return r.json(); }).then(function(items) {
        state.items = Array.isArray(items) ? items : [];
        render();
      }).catch(function() { state.items = []; render(); });
    }

    function deleteIds(ids) {
      if (!ids.length) { return Promise.resolve(); }
      return fetch("/api/delete?ids=" + encodeURIComponent(ids.join(","))).then(function(r) { return r.json(); });
    }

    document.addEventListener("DOMContentLoaded", function() {
      syncHeaderOffset();
      window.addEventListener("resize", syncHeaderOffset);
      document.getElementById("search").addEventListener("input", function(e) {
        state.filter = e.target.value;
        render();
      });
      document.getElementById("reload").addEventListener("click", load);
      document.querySelector("thead").addEventListener("click", function(e) {
        var t = e.target.closest("[data-sort]");
        if (t) { setSort(t.getAttribute("data-sort")); }
      });
      document.getElementById("selectAll").addEventListener("change", function(e) {
        var boxes = document.querySelectorAll("tbody input[type=checkbox]");
        Array.prototype.forEach.call(boxes, function(b) { b.checked = e.target.checked; });
        updateButtons();
      });
      document.getElementById("deleteSelected").addEventListener("click", function() {
        var ids = selectedIds();
        if (!ids.length) { return; }
        deleteIds(ids).then(load);
      });
      // Two-click confirm (avoids relying on window.confirm in the special page).
      var armed = false;
      var allBtn = document.getElementById("deleteAll");
      allBtn.addEventListener("click", function() {
        if (!armed) {
          armed = true;
          allBtn.textContent = "Click again to delete ALL";
          setTimeout(function() { armed = false; allBtn.textContent = "Delete all"; }, 3000);
          return;
        }
        armed = false;
        allBtn.textContent = "Delete all";
        fetch("/api/deleteAll").then(function(r) { return r.json(); }).then(load);
      });
      load();
    });
    """
}
