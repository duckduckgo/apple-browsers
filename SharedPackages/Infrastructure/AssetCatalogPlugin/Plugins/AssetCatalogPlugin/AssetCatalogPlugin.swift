//
//  AssetCatalogPlugin.swift
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

import Foundation
import PackagePlugin

/// Compiles the target's `*.xcassets` with Xcode's own `actool` for `swift build`,
/// which neither compiles asset catalogs nor generates asset symbols. Mirrors
/// Xcode's `GenerateAssetSymbols` and `CompileAssetCatalog` build steps:
/// - `GeneratedAssetSymbols-<Catalog>.swift` provides the same
///   `ImageResource`/`ColorResource` symbols Xcode generates for packages;
/// - `Assets.car` is added to the target's resource bundle (`Bundle.module`).
///
/// For macOS `swift build` only (VSCode/Cursor builds, SourceKit-LSP). Keep the
/// catalog in the target's `resources:`: under Xcode the plugin does nothing and
/// Xcode processes the catalog itself. (In the plugin sandbox actool can't reach
/// CoreSimulator, so it can't compile iOS catalogs.)
///
/// Not compatible with `swift build --build-system swiftbuild`, which compiles
/// the catalog itself too; it doesn't need the plugin.
@main
struct AssetCatalogPlugin: BuildToolPlugin {

    /// The macOS app's deployment target; build settings aren't available here.
    static let minimumDeploymentTarget = "12.3"

    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        guard !isXcodeBuild(context) else { return [] }
        let catalogs = findCatalogs(in: URL(fileURLWithPath: target.directory.string))
        guard !catalogs.isEmpty else { return [] }

        let workDir = context.pluginWorkDirectory
        let bundleID = "\(context.package.id).\(target.name)"
        let catalogCommands = catalogs.flatMap { catalog in
            [
                symbolsCommand(catalog, workDir: workDir, bundleID: bundleID),
                compileCommand(catalog, workDir: workDir),
            ]
        }
        return catalogCommands + [try infoPlistCommand(workDir: workDir, bundleID: bundleID)]
    }

    /// Xcode's `GenerateAssetSymbols` step. actool only writes symbols when
    /// `--bundle-identifier` is passed, and then it doesn't write `Assets.car`.
    /// Symbol extensions (`NSImage.foo`) are off, as in Xcode package builds.
    private func symbolsCommand(_ catalog: URL, workDir: Path, bundleID: String) -> Command {
        let name = catalog.deletingPathExtension().lastPathComponent
        let outDir = workDir.appending(name, "symbols")
        let symbols = outDir.appending("GeneratedAssetSymbols-\(name).swift")
        let arguments = actoolArguments(catalog, outDir: outDir) + [
            "--bundle-identifier", bundleID,
            "--generate-swift-asset-symbols", symbols.string,
            "--generate-swift-asset-symbol-extensions", "NO",
        ]
        return .buildCommand(displayName: "Generate asset symbols for \(catalog.lastPathComponent)",
                             executable: Path("/usr/bin/xcrun"),
                             arguments: arguments,
                             inputFiles: catalogFiles(catalog),
                             outputFiles: [symbols])
    }

    /// Xcode's `CompileAssetCatalog` step. `Assets.car` isn't a source file,
    /// so it's copied into the target's resource bundle.
    private func compileCommand(_ catalog: URL, workDir: Path) -> Command {
        let name = catalog.deletingPathExtension().lastPathComponent
        let outDir = workDir.appending(name, "car")
        return .buildCommand(displayName: "Compile asset catalog \(catalog.lastPathComponent)",
                             executable: Path("/usr/bin/xcrun"),
                             arguments: actoolArguments(catalog, outDir: outDir),
                             inputFiles: catalogFiles(catalog),
                             outputFiles: [outDir.appending("Assets.car")])
    }

    private func actoolArguments(_ catalog: URL, outDir: Path) -> [String] {
        [
            "actool", catalog.path,
            "--compile", outDir.string,
            "--output-format", "human-readable-text",
            "--errors", "--warnings",
            "--platform", "macosx",
            "--target-device", "mac",
            "--minimum-deployment-target", Self.minimumDeploymentTarget,
            "--output-partial-info-plist", outDir.appending("partial-info.plist").string,
        ]
    }

    /// `swift build` produces a flat resource bundle without Info.plist, and
    /// CoreUI ignores `Assets.car` in a bundle without `CFBundleIdentifier`.
    private func infoPlistCommand(workDir: Path, bundleID: String) throws -> Command {
        let template = workDir.appending("Info.plist.template")
        let plist = ["CFBundleIdentifier": bundleID, "CFBundlePackageType": "BNDL"]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try write(data, to: template)
        let output = workDir.appending("plist", "Info.plist")
        return .buildCommand(displayName: "Write resource bundle Info.plist",
                             executable: Path("/usr/bin/ditto"),
                             arguments: [template.string, output.string],
                             inputFiles: [template],
                             outputFiles: [output])
    }

    /// Xcode runs package plugins in `…/BuildToolPluginIntermediates/…`;
    /// SwiftPM uses `<scratch path>/plugins/outputs/…`.
    private func isXcodeBuild(_ context: PluginContext) -> Bool {
        context.pluginWorkDirectory.string.contains("/BuildToolPluginIntermediates/")
    }

    private func findCatalogs(in directory: URL) -> [URL] {
        let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)
        var catalogs: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "xcassets" else { continue }
            catalogs.append(url)
            enumerator?.skipDescendants()
        }
        return catalogs.sorted { $0.path < $1.path }
    }

    /// All files inside the catalog, so any asset change reruns actool.
    private func catalogFiles(_ catalog: URL) -> [Path] {
        let enumerator = FileManager.default.enumerator(at: catalog, includingPropertiesForKeys: nil)
        var files = [Path(catalog.path)]
        while let url = enumerator?.nextObject() as? URL {
            files.append(Path(url.path))
        }
        return files
    }

    /// Writes only when changed, so the file doesn't invalidate the build.
    private func write(_ data: Data, to path: Path) throws {
        let url = URL(fileURLWithPath: path.string)
        guard (try? Data(contentsOf: url)) != data else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }
}
