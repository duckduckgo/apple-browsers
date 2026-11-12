---
name: ddg-xcode-add-file
description: Use when creating, moving, renaming or deleting a file or folder that belongs to the iOS or macOS Xcode project rather than a Swift package.
---

# Add, move or delete a file in the Xcode projects

Files inside a Swift package (`SharedPackages/`, `iOS/LocalPackages/`, `macOS/LocalPackages/`) need
no project change: SwiftPM reads them from disk. For everything else, what to do depends on how the
destination folder is represented in `iOS/DuckDuckGo-iOS.xcodeproj/project.pbxproj` or
`macOS/DuckDuckGo-macOS.xcodeproj/project.pbxproj`.

1. **Classify the destination.** On macOS, every folder outside `macOS/LocalPackages/` is a
   **buildable folder**: go to step 2. On iOS, for each ancestor folder, nearest first, run
   `grep "path = <FolderName>;" <project.pbxproj> | grep PBXFileSystemSynchronizedRootGroup`.
   A match is a **buildable folder**; no match all the way up is a **group**. If a folder name is
   ambiguous, confirm the match's ID is listed in the parent group's `children`.
   `iOS/DuckDuckGo/` itself and `iOS/DuckDuckGoTests/` are still groups.
2. **Buildable folder:** create, move or delete the file on disk and stop. A pbxproj entry on top
   of that compiles the file twice. The folder decides the targets: on macOS, a file under
   `macOS/DuckDuckGo/` builds into both `DuckDuckGo Privacy Browser` and
   `DuckDuckGo Privacy Browser App Store`, and one under `macOS/UnitTests/` into both `Unit Tests`
   targets. If the file needs a different target than its folder gives it, mirror an existing
   `PBXFileSystemSynchronizedBuildFileExceptionSet`, or ask the user to set it in Xcode's File
   Inspector. Everything in the folder ships, so don't leave notes, `.md` files or stray copies
   there unless an exception set excludes them.
3. **Group (iOS only):** pick a sibling file with the same target membership and copy its entries with fresh
   IDs (`python3 -c "import secrets; print(secrets.token_hex(12).upper())"`, then `grep` that each
   ID is unused):
   - one `PBXFileReference`
   - one `PBXBuildFile` per target
   - one child line in the parent `PBXGroup`
   - one line in each target's `PBXSourcesBuildPhase`

   Moving or deleting a file removes the same entries.
4. **Edit surgically.** Insert or delete lines anchored on the sibling's exact lines. Never
   re-serialize the file, for example with the `xcodeproj` gem: it rewrites package references and
   produces an unreviewable diff.
5. **New directory under an iOS group:** ask the user to create it in Xcode as a folder
   (File ▸ New ▸ Folder) so it becomes a buildable folder. Converting existing groups belongs in
   dedicated migration PRs that use Xcode's Convert to Folder.

Done when `plutil -lint` passes on the project file, its `git diff` holds only the lines for your
files (none for a buildable folder, unless you added an exception), and each file is in every
target its siblings are in.
