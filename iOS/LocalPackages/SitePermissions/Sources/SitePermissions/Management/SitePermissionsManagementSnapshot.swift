//
//  SitePermissionsManagementSnapshot.swift
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

public struct SitePermissionsManagementSnapshot: Equatable, Sendable {

    public let site: SitePermissionKey
    public let isFireMode: Bool
    public let storedPermissions: SitePermissionsStore.SitePermissionRecord
    public let ephemeralPermissionTypes: Set<SitePermissionType>
    public let siteAllowedPermissionTypesThisVisit: Set<SitePermissionType>
    public let requestedPermissionTypesThisVisit: Set<SitePermissionType>
    public let captureStates: [SitePermissionType: SitePermissionCaptureState]
    public let systemAuthorizationStates: [SitePermissionType: SystemPermissionAuthorizationState]
    public let systemBlockedPermissionTypes: Set<SitePermissionType>

    public init(site: SitePermissionKey,
                isFireMode: Bool = false,
                storedPermissions: SitePermissionsStore.SitePermissionRecord,
                ephemeralPermissionTypes: Set<SitePermissionType>,
                siteAllowedPermissionTypesThisVisit: Set<SitePermissionType>,
                requestedPermissionTypesThisVisit: Set<SitePermissionType>,
                captureStates: [SitePermissionType: SitePermissionCaptureState],
                systemAuthorizationStates: [SitePermissionType: SystemPermissionAuthorizationState],
                systemBlockedPermissionTypes: Set<SitePermissionType>) {
        self.site = site
        self.isFireMode = isFireMode
        self.storedPermissions = storedPermissions.cameraAndMicrophoneOnly
        self.ephemeralPermissionTypes = ephemeralPermissionTypes.cameraAndMicrophoneOnly
        self.siteAllowedPermissionTypesThisVisit = siteAllowedPermissionTypesThisVisit.cameraAndMicrophoneOnly
        self.requestedPermissionTypesThisVisit = requestedPermissionTypesThisVisit.cameraAndMicrophoneOnly
        self.captureStates = captureStates.filter { Self.cameraAndMicrophoneTypes.contains($0.key) }
        self.systemAuthorizationStates = systemAuthorizationStates.filter { Self.cameraAndMicrophoneTypes.contains($0.key) }
        self.systemBlockedPermissionTypes = systemBlockedPermissionTypes.cameraAndMicrophoneOnly
    }

    public var relevantPermissionTypes: Set<SitePermissionType> {
        let activeCaptureTypes = Set(captureStates.compactMap { entry in
            entry.value == .inactive ? nil : entry.key
        })
        return Set(storedPermissions.keys)
            .union(ephemeralPermissionTypes)
            .union(siteAllowedPermissionTypesThisVisit)
            .union(requestedPermissionTypesThisVisit)
            .union(activeCaptureTypes)
    }

    /// Requested-only state affects sheet rows, but does not make the browser menu entry visible.
    public var showsMenuEntry: Bool {
        !storedPermissions.isEmpty
            || !ephemeralPermissionTypes.isEmpty
            || !siteAllowedPermissionTypesThisVisit.isEmpty
            || captureStates.contains { $0.value != .inactive }
    }

    static let cameraAndMicrophoneTypes: Set<SitePermissionType> = [.camera, .microphone]
}

private extension Dictionary where Key == SitePermissionType, Value == SitePermissionDecision {
    var cameraAndMicrophoneOnly: Self {
        filter { SitePermissionsManagementSnapshot.cameraAndMicrophoneTypes.contains($0.key) }
    }
}

private extension Set where Element == SitePermissionType {
    var cameraAndMicrophoneOnly: Self {
        intersection(SitePermissionsManagementSnapshot.cameraAndMicrophoneTypes)
    }
}
