//
//  TakeScreenshotTool.swift
//  AXION
//
//  Created by Thomas Chamard on 22/06/2026.
//

import Foundation

final class TakeScreenshotTool: Tool {
    let name = "take_screenshot"

    func execute(argument: String) async -> ToolExecutionResult {
        let path = clean(argument)
        let expandedPath = (path as NSString).expandingTildeInPath

        guard !expandedPath.isEmpty else {
            return .failure(title: "Missing screenshot path")
        }

        let directory = URL(fileURLWithPath: expandedPath).deletingLastPathComponent()

        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        } catch {
            return .failure(title: "Failed to create screenshot directory")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", expandedPath]

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                return .success(title: "Screenshot saved", detail: expandedPath)
            }

            return .failure(title: "Failed to take screenshot")
        } catch {
            return .failure(title: "Failed to take screenshot")
        }
    }

    private func clean(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
    }
}
