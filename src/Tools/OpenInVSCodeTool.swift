//
//  OpenInVSCodeTool.swift
//  AXION
//
//  Created by Thomas Chamard on 22/06/2026.
//

import Foundation

final class OpenInVSCodeTool: Tool {
    let name = "open_in_vscode"

    func execute(argument: String) -> ToolExecutionResult {
        let path = clean(argument)
        let expandedPath = (path as NSString).expandingTildeInPath

        guard FileManager.default.fileExists(atPath: expandedPath) else {
            return .failure(title: "Path not found", detail: expandedPath)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Visual Studio Code", expandedPath]

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                return .success(title: "Opened in VSCode", detail: expandedPath)
            }

            return .failure(title: "Failed to open in VSCode")
        } catch {
            return .failure(title: "Failed to open in VSCode")
        }
    }

    private func clean(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
    }
}
