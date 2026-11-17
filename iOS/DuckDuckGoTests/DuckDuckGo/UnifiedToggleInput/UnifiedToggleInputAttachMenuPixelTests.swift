//
//  UnifiedToggleInputAttachMenuPixelTests.swift
//  DuckDuckGo
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

import AIChat
import Core
@_spi(Testing) import PixelKit
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import DuckDuckGo

@MainActor
@Suite("Attach menu pixels")
struct UnifiedToggleInputAttachMenuPixelTests {

    private static let surfaces: [UnifiedToggleInputPixelSurface] = [.addressBar, .duckAI, .contextualChat]

    // MARK: - Reporter: name, params and frequency

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: surfaces)
    func shownReportsNameSurfaceAndDailyAndCount(surface: UnifiedToggleInputPixelSurface) {
        let pixelKit = PixelKitMock()

        makeReporter(pixelKit, surface: surface).reportAttachMenuShown()

        let call = pixelKit.actualFireCalls.last
        #expect(pixelKit.actualFireCalls.count == 1)
        #expect(call?.pixel.name == "m_aichat_unified_input_attach_menu_shown")
        #expect(call?.pixel.parameters == ["surface": surface.rawValue])
        #expect(call?.frequency == .dailyAndCount)
        #expect(call?.includeAppVersionParameter == true)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: UnifiedToggleInputAttachMenuItem.allCases, surfaces)
    func itemSelectedReportsNameItemSurfaceAndDailyAndCount(item: UnifiedToggleInputAttachMenuItem,
                                                            surface: UnifiedToggleInputPixelSurface) {
        let pixelKit = PixelKitMock()

        makeReporter(pixelKit, surface: surface).reportAttachMenuItemSelected(item)

        let call = pixelKit.actualFireCalls.last
        #expect(pixelKit.actualFireCalls.count == 1)
        #expect(call?.pixel.name == "m_aichat_unified_input_attach_menu_item_selected")
        #expect(call?.pixel.parameters == ["surface": surface.rawValue, "item": item.rawValue])
        #expect(call?.frequency == .dailyAndCount)
        #expect(call?.includeAppVersionParameter == true)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func itemParamValuesMatchTheDefinition() {
        #expect(UnifiedToggleInputAttachMenuItem.allCases.map(\.rawValue)
                == ["camera", "photo_library", "file_picker", "page", "recent_tab", "tab_picker"])
    }

    // MARK: - Presenter: each enabled item reports itself

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: [
        (UserText.aiChatAttachmentOptionAttachPhoto, UnifiedToggleInputAttachMenuItem.photoLibrary),
        (UserText.aiChatAttachmentOptionAttachFile, .filePicker),
        (UserText.aiChatAttachmentOptionAskAboutPage, .page),
        (UserText.aiChatAttachmentOptionAddTabs, .tabPicker),
        ("Recent tab", .recentTab)
    ])
    func enabledItemReportsSelection(title: String, expected: UnifiedToggleInputAttachMenuItem) throws {
        var selected: [UnifiedToggleInputAttachMenuItem] = []
        let menu = try #require(makeMenu(onItemSelected: { selected.append($0) }))

        try action(titled: title, in: menu).performWithSender(nil, target: nil)

        #expect(selected == [expected])
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func cameraReportsSelectionOnlyWhenACameraExists() throws {
        var selected: [UnifiedToggleInputAttachMenuItem] = []
        let menu = try #require(makeMenu(onItemSelected: { selected.append($0) }))
        let camera = try action(titled: UserText.aiChatAttachmentOptionTakePhoto, in: menu)

        camera.performWithSender(nil, target: nil)

        let hasCamera = UIImagePickerController.isSourceTypeAvailable(.camera)
        #expect(camera.attributes.contains(.disabled) == !hasCamera)
        #expect(selected == (hasCamera ? [.camera] : []))
    }

    // MARK: - Presenter: disabled items stay silent

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func disabledItemsDoNotReportSelection() throws {
        var selected: [UnifiedToggleInputAttachMenuItem] = []
        let presenter = UnifiedToggleInputAttachmentPresenter()
        let attached = candidate("attached")
        let menu = try #require(presenter.makeAttachmentMenu(
            presenterProvider: { nil },
            onItemSelected: { selected.append($0) },
            photoSelectionLimit: 0,
            canAttachFile: false,
            allowedFileTypes: [.pdf],
            showsPageContextAction: true,
            pageContextActionHandler: nil,
            attachableTabs: [attached, candidate("Recent tab")],
            attachedTabIds: [attached.tabId],
            tabAttachmentLimit: 1,
            isTabSelectionAvailable: { false },
            tabActionHandler: { _, _, _ in .changed }
        ))
        let disabledTitles = [UserText.aiChatAttachmentOptionTakePhoto,
                              UserText.aiChatAttachmentOptionAttachPhoto,
                              UserText.aiChatAttachmentOptionAttachFile,
                              UserText.aiChatAttachmentOptionAskAboutPage,
                              "Recent tab"]

        for title in disabledTitles {
            let action = try action(titled: title, in: menu)
            #expect(action.attributes.contains(.disabled), "\(title)")
            action.performWithSender(nil, target: nil)
        }
        try action(titled: UserText.aiChatAttachmentOptionAddTabs, in: menu).performWithSender(nil, target: nil)

        #expect(selected.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func attachedRecentTabAtTheLimitStillReportsSelection() throws {
        var selected: [UnifiedToggleInputAttachMenuItem] = []
        let attached = candidate("attached")
        let menu = try #require(UnifiedToggleInputAttachmentPresenter().makeAttachmentMenu(
            presenterProvider: { nil },
            onItemSelected: { selected.append($0) },
            photoSelectionLimit: 0,
            canAttachFile: false,
            allowedFileTypes: [],
            attachableTabs: [attached],
            attachedTabIds: [attached.tabId],
            tabAttachmentLimit: 1,
            tabActionHandler: { _, _, _ in .changed }
        ))

        try action(titled: "attached", in: menu).performWithSender(nil, target: nil)

        #expect(selected == [.recentTab])
    }

    // MARK: - Toolbar: menu opens

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func attachButtonTouchDownReportsShownWhenMenuIsSetAndEnabled() throws {
        let toolbar = UnifiedToggleInputToolbarView()
        var shownCount = 0
        toolbar.onAttachMenuShown = { shownCount += 1 }
        toolbar.attachmentMenu = UIMenu(children: [UIAction(title: "Attach") { _ in }])
        toolbar.isImageButtonEnabled = true

        toolbar.imageButton.sendActions(for: .touchDown)

        #expect(shownCount == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func attachButtonTouchDownDoesNotReportShownWithoutAMenu() {
        let toolbar = UnifiedToggleInputToolbarView()
        var shownCount = 0
        toolbar.onAttachMenuShown = { shownCount += 1 }
        toolbar.attachmentMenu = nil
        toolbar.isImageButtonEnabled = true

        toolbar.imageButton.sendActions(for: .touchDown)

        #expect(shownCount == 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func attachButtonTouchDownDoesNotReportShownWhenDisabled() {
        let toolbar = UnifiedToggleInputToolbarView()
        var shownCount = 0
        toolbar.onAttachMenuShown = { shownCount += 1 }
        toolbar.attachmentMenu = UIMenu(children: [UIAction(title: "Attach") { _ in }])
        toolbar.isImageButtonEnabled = false

        toolbar.imageButton.sendActions(for: .touchDown)

        #expect(shownCount == 0)
    }

    // MARK: - Helpers

    private func makeReporter(_ pixelKit: PixelKitMock, surface: UnifiedToggleInputPixelSurface) -> UTIPixelReporter {
        UTIPixelReporter(firing: UTIPixelFiring(pixelKit: { pixelKit }), context: {
            UTIPixelContext(surface: surface, isDuckAISurfaceForAttribution: false, inputMode: .aiChat,
                            isToggleVisible: false, pageType: .unknown, duckAIEntrySource: nil)
        })
    }

    /// Every item enabled: photos and files allowed, page context attachable, tabs available.
    private func makeMenu(onItemSelected: @escaping (UnifiedToggleInputAttachMenuItem) -> Void) -> UIMenu? {
        UnifiedToggleInputAttachmentPresenter().makeAttachmentMenu(
            presenterProvider: { nil },
            onItemSelected: onItemSelected,
            photoSelectionLimit: 3,
            canAttachFile: true,
            allowedFileTypes: [.pdf],
            showsPageContextAction: true,
            pageContextActionHandler: {},
            attachableTabs: [candidate("Recent tab")],
            attachedTabIds: [],
            tabAttachmentLimit: 3,
            isTabSelectionAvailable: { true },
            tabActionHandler: { _, _, _ in .changed }
        )
    }

    private func candidate(_ title: String) -> MultiTabAttachmentCandidate {
        MultiTabAttachmentCandidate(tabId: title, title: title, url: URL(string: "https://example.com")!)
    }

    private func action(titled title: String, in menu: UIMenu) throws -> UIAction {
        let actions = menu.children.flatMap { element -> [UIMenuElement] in
            (element as? UIMenu)?.children ?? [element]
        }.compactMap { $0 as? UIAction }
        return try #require(actions.first { $0.title == title }, "no action titled \(title)")
    }
}
