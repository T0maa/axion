//
//  ShowNotificationTool.swift
//  AXION
//
//  Created by Thomas Chamard on 22/06/2026.
//

import Foundation

final class ShowNotificationTool: Tool {
    let name = "show_notification"

    func execute(argument: String) -> ToolExecutionResult {
        let parts = argument.split(separator: "|", maxSplits: 1).map(String.init)

        let title = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = parts.count > 1
            ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            : ""

        guard let title, !title.isEmpty else {
            return .failure(title: "Missing notification title")
        }

        let script = """
        display notification "\(escape(message))" with title "\(escape(title))"
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                return .success(title: "Notification shown")
            }

            return .failure(title: "Failed to show notification")
        } catch {
            return .failure(title: "Failed to show notification")
        }
    }

    private func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
