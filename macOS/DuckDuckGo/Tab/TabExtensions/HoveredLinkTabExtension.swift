//
//  HoveredLinkTabExtension.swift
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
import Foundation
import DDGNavigation

final class HoveredLinkTabExtension: TabExtension {

    private var cancellable: AnyCancellable?
    private weak var hoverUserScript: HoverUserScript?
    fileprivate var hoveredLinkSubject = CurrentValueSubject<URL?, Never>(nil)

    init(hoverUserScriptPublisher: some Publisher<HoverUserScript?, Never>) {
        cancellable = hoverUserScriptPublisher.sink { [weak self] hoverUserScript in
            self?.hoverUserScript = hoverUserScript
            hoverUserScript?.delegate = self
        }
    }

    /// The page the link was hovered on is gone: neither the script nor consumers may keep reporting it.
    func resetForNewDocument() {
        hoverUserScript?.resetForNewDocument()
        guard hoveredLinkSubject.value != nil else { return }
        hoveredLinkSubject.send(nil)
    }

}

extension HoveredLinkTabExtension: HoverUserScriptDelegate {
    @MainActor
    func hoverUserScript(_ script: HoverUserScript, didChange url: URL?) {
        hoveredLinkSubject.send(url)
    }
}

extension HoveredLinkTabExtension: NavigationResponder {

    func didCommit(_ navigation: Navigation) {
        resetForNewDocument()
    }

}

protocol HoveredLinksProtocol: AnyObject, NavigationResponder {
    var hoveredLinkPublisher: AnyPublisher<URL?, Never> { get }
    /// The link under the pointer as last reported by the page. The page reports only changes,
    /// so this is the only way to learn it again after a consumer has forgotten it.
    var currentHoveredLink: URL? { get }
}

extension HoveredLinkTabExtension: HoveredLinksProtocol {
    func getPublicProtocol() -> HoveredLinksProtocol { self }

    /// Reports link changes only: the current value, which a new subscriber would get first, is read from `currentHoveredLink`.
    var hoveredLinkPublisher: AnyPublisher<URL?, Never> {
        hoveredLinkSubject.dropFirst().eraseToAnyPublisher()
    }

    var currentHoveredLink: URL? {
        hoveredLinkSubject.value
    }
}

extension TabExtensions {
    var hoveredLinks: HoveredLinksProtocol? {
        resolve(HoveredLinkTabExtension.self)
    }
}

extension Tab {
    var currentHoveredLink: URL? {
        self.hoveredLinks?.currentHoveredLink
    }

    var hoveredLinkPublisher: AnyPublisher<URL?, Never> {
        self.hoveredLinks?.hoveredLinkPublisher ?? Just(nil).eraseToAnyPublisher()
    }
}
