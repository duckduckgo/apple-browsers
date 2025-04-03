//
//  SwiftLintPlugin.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

@main
struct SwiftLintPlugin: BuildToolPlugin {

    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        // disable output for SPM modules built in RELEASE mode
        guard let target = target as? SourceModuleTarget else {
            assertionFailure("invalid target")
            return []
        }

        guard (target as? SwiftSourceModuleTarget)?.compilationConditions.contains(.debug) != false || target.kind == .test else {
            print("SwiftLint: \(target.name): Skipping for RELEASE build")
            return []
        }

        let inputFiles = target.sourceFiles(withSuffix: "swift").map(\.path)
        guard !inputFiles.isEmpty else {
            print("SwiftLint: \(target.name): No input files")
            return []
        }

        return try createBuildCommands(
            target: target.name,
            inputFiles: inputFiles,
            packageDirectory: context.package.directory.firstParentContainingConfigFile() ?? context.package.directory,
            workingDirectory: context.pluginWorkDirectory,
            tool: context.tool(named:)
        )
    }

    private func createBuildCommands(
        target: String,
        inputFiles: [Path],
        packageDirectory: Path,
        workingDirectory: Path,
        tool: (String) throws -> PluginContext.Tool
    ) throws -> [Command] {

        // only lint when built from Xcode (disable for CI or xcodebuild)
        guard case .xcode = ProcessInfo().environmentType else { return [] }

        let fm = FileManager()

        let cacheURL = URL(fileURLWithPath: workingDirectory.appending("cache.json").string)
        let outputPath = workingDirectory.appending("output.txt").string

        // if clean build: clear cache
        let buildDir = workingDirectory.removingLastComponent() // BrowserServicesKit
            .removingLastComponent() // browserserviceskit.output
            .removingLastComponent() // plugins
            .removingLastComponent() // SourcePackages
            .removingLastComponent() // DerivedData/DuckDuckGo-xxxx
            .appending("Build")
        if let buildDirContents = try? fm.contentsOfDirectory(atPath: buildDir.string),
           !buildDirContents.contains("Products") {
            print("SwiftLint: \(target): Clean Build")

            try? fm.removeItem(at: cacheURL)
            try? fm.removeItem(atPath: outputPath)
        }

        // read cached data
        var cache = (try? JSONDecoder().decode([String: InputListItem].self, from: Data(contentsOf: cacheURL))) ?? [:]
        // read diagnostics from last pass
        let lastOutput = cache.isEmpty ? "" : (try? String(contentsOfFile: outputPath)) ?? {
            // no diagnostics file – reset
            cache = [:]
            return ""
        }()

        // analyze new/modified files and output cached diagnostics for non-modified files
        var filesToProcess = Set<String>()
        var newCache = [String: InputListItem]()
        for inputFile in inputFiles {
            try autoreleasepool {

                let modified = try inputFile.modified
                if let cacheItem = cache[inputFile.string], modified == cacheItem.modified {
                    // file not modified
                    newCache[inputFile.string] = cacheItem
                    return
                }

                // updated modification date in cache and re-process
                newCache[inputFile.string] = .init(modified: modified)

                filesToProcess.insert(inputFile.string)
            }
        }

        // merge diagnostics from last linter pass into cache
        for outputLint in lastOutput.split(separator: "\n") {
            guard let filePath = outputLint.split(separator: ":", maxSplits: 1).first.map(String.init),
                  !filesToProcess.contains(filePath) else { continue }

            newCache[filePath]?.appendDiagnosticsMessage(String(outputLint))
        }

        // collect cached diagnostic messages from cache
        let cachedDiagnostics = newCache.values.reduce(into: [String]()) {
            $0 += $1.diagnostics ?? []
        }

        // We are not producing output files and this is needed only to not include cache files into bundle
        let outputFilesDirectory = workingDirectory.appending("Output")
        try? fm.createDirectory(at: outputFilesDirectory.url, withIntermediateDirectories: true)
        try? fm.removeItem(at: cacheURL.appendingPathExtension("tmp"))
        try? fm.removeItem(atPath: outputPath + ".tmp")

        var result = [Command]()
        if !filesToProcess.isEmpty {
            print("SwiftLint: \(target): Processing \(filesToProcess.count) files")

            // write updated cache into temporary file, cache file will be overwritten when linting completes
            try JSONEncoder().encode(newCache).write(to: cacheURL.appendingPathExtension("tmp"))

            let swiftlint = try tool("swiftlint").path
            let lintCommand = """
            cd "\(packageDirectory)" && "\(swiftlint)" lint --quiet --force-exclude --cache-path "\(workingDirectory)" \
                \(filesToProcess.map { "\"\($0)\"" }.joined(separator: " ")) \
                | tee -a "\(outputPath).tmp"
            """

            result = [
                .prebuildCommand(
                    displayName: "\(target): SwiftLint",
                    executable: .sh,
                    arguments: ["-c", lintCommand],
                    outputFilesDirectory: outputFilesDirectory
                )
            ]

        } else {
            print("SwiftLint: \(target): No new files to process")
            try JSONEncoder().encode(newCache).write(to: cacheURL)
            try "".write(toFile: outputPath, atomically: false, encoding: .utf8)
        }

        // output cached diagnostic messages from previous run
        result.append(.prebuildCommand(
            displayName: "SwiftLint: \(target): cached \(cacheURL.path)",
            executable: .echo,
            arguments: [cachedDiagnostics.joined(separator: "\n")],
            outputFilesDirectory: outputFilesDirectory
        ))

        if !filesToProcess.isEmpty {
            // when ready put temporary cache and output into place
            result.append(.prebuildCommand(
                displayName: "SwiftLint: \(target): Cache results",
                executable: .mv,
                arguments: ["\(outputPath).tmp", outputPath],
                outputFilesDirectory: outputFilesDirectory
            ))
            result.append(.prebuildCommand(
                displayName: "SwiftLint: \(target): Cache source files modification dates",
                executable: .mv,
                arguments: [cacheURL.appendingPathExtension("tmp").path, cacheURL.path],
                outputFilesDirectory: outputFilesDirectory
            ))
        }

        return result
    }
}

#if canImport(XcodeProjectPlugin)

import XcodeProjectPlugin

extension SwiftLintPlugin: XcodeBuildToolPlugin {
    func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command] {
        let inputFiles = target.inputFiles.filter {
            $0.type == .source && $0.path.extension == "swift"
        }.map(\.path)

        guard !inputFiles.isEmpty else {
            print("SwiftLint: \(target): No input files")
            return []
        }

        return try createBuildCommands(
            target: target.displayName,
            inputFiles: inputFiles,
            packageDirectory: context.xcodeProject.directory,
            workingDirectory: context.pluginWorkDirectory,
            tool: context.tool(named:)
        )
    }
}

#endif

extension String {
    static let swiftlintConfigFileName = ".swiftlint.yml"

    static let debug = "DEBUG"
}
