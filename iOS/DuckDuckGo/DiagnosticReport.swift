//
//  DiagnosticReport.swift
//  DuckDuckGo
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

import BrowserServicesKit
import Common
import Configuration
import Core
import Crashes
import DDGSync
import Kingfisher
import LinkPresentation
import VPN
import Persistence
import SwiftUI
import UIKit
import WebKit

protocol DiagnosticReportDataSourceDelegate: AnyObject {

    func dataGatheringStarted()
    func dataGatheringComplete()

}

class DiagnosticReportDataSource: UIActivityItemProvider {

    weak var delegate: DiagnosticReportDataSourceDelegate?
    var fireproofing: Fireproofing?
    var tabManager: TabManager?

    @UserDefaultsWrapper(key: .lastConfigurationRefreshDate, defaultValue: .distantPast)
    private var lastRefreshDate: Date

    convenience init(delegate: DiagnosticReportDataSourceDelegate, tabManager: TabManager, fireproofing: Fireproofing) {
        self.init(placeholderItem: "")
        self.delegate = delegate
        self.tabManager = tabManager
        self.fireproofing = fireproofing
    }

    override var item: Any {
        delegate?.dataGatheringStarted()

        let report = [reportHeader(),
                      tabsReport(),
                      imageCacheReport(),
                      fireproofingReport(),
                      configurationReport(),
                      cookiesReport()].joined(separator: "\n\n")

        delegate?.dataGatheringComplete()
        return report
    }

    override func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = "Diagnostic Report"
        return metadata
    }

    func reportHeader() -> String {
        """
        # DuckDuckGo App Diagnostic Report
        Date: \(String(describing: Date()))
        Version: \(AppVersion.shared.versionAndBuildNumber)
        """
    }

    func fireproofingReport() -> String {
        let allowedDomains = fireproofing?.allowedDomains.map { "* \($0)" } ?? []

        let allowedDomainsEntry = ["### Allowed Domains"] + (allowedDomains.isEmpty ? [""] : allowedDomains)

        return (["## Fireproofing Report"] + allowedDomainsEntry).joined(separator: "\n")
    }

    func imageCacheReport() -> String {
        """
        ## Image Cache Report
        Bookmark Cache: \(Favicons.Constants.caches[.fireproof]?.count ?? -1)
        Tabs Cache: \(Favicons.Constants.caches[.tabs]?.count ?? -1)
        """
    }

    func configurationReport() -> String {
        let etagStorage = DebugEtagStorage()
        let configs = Configuration.allCases.map { $0.rawValue + ": " + (etagStorage.loadEtag(for: $0.storeKey) ?? "<none>") }
        let lastRefreshDate = "Last refresh date: \(lastRefreshDate == .distantPast ? "Never" : String(describing: lastRefreshDate))"
        return (["## Configuration Report"] + [lastRefreshDate] + configs).joined(separator: "\n")
    }

    func cookiesReport() -> String {
        var cookies = [HTTPCookie]()

        let group = DispatchGroup()
        group.enter()
        DispatchQueue.main.async {
            WKWebsiteDataStore.current().httpCookieStore.getAllCookies { httpCookies in
                cookies = httpCookies
                group.leave()
            }
        }

        var timeout = [String]()
        if group.wait(timeout: .now() + 10) == .timedOut {
            timeout = ["Failed to retrieve cookies in 10 seconds"]
        }

        let processedCookies = cookies
            .sorted(by: { $0.domain < $1.domain })
            .sorted(by: { $0.name < $1.name })
            .map { $0.debugString }

        return (["## Cookie Report"] + timeout + processedCookies).joined(separator: "\n")
    }

    func tabsReport() -> String {
        """
        ### Tabs Report
        Tabs: \(tabManager?.count ?? -1)
        """
    }

}

private extension ImageCache {

    var count: Int {
        let url = diskStorage.directoryURL
        do {
            let contents = try FileManager.default.contentsOfDirectory(atPath: url.path)
            return contents.count
        } catch {
            return -2
        }
    }

}

private extension HTTPCookie {

    var debugString: String {
        """
        \(domain)\(path):\(name)=\(value.isEmpty ? "<blank>" : "<value>")\(expiresDate != nil ? ";expires=\(String(describing: expiresDate!))" : "")
        """
    }

}
