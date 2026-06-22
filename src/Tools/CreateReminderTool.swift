//
//  CreateReminderTool.swift
//  AXION
//
//  Created by Thomas Chamard on 22/06/2026.
//

import Foundation

final class CreateReminderTool: Tool {
    let name = "create_reminder"

    func execute(argument: String) -> String {
        let parts = argument.split(separator: "|", maxSplits: 1).map(String.init)

        let title = clean(parts.first ?? "")
        let dueDate = parts.count > 1 ? clean(parts[1]) : ""

        guard !title.isEmpty else {
            return "Missing reminder title."
        }

        let script: String

        if dueDate.isEmpty {
            script = """
            tell application "Reminders"
                make new reminder with properties {name:"\(escape(title))"}
            end tell
            """
        } else {
            script = """
            tell application "Reminders"
                set dueDate to date "\(escape(dueDate))"
                make new reminder with properties {name:"\(escape(title))", due date:dueDate}
            end tell
            """
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                return "Reminder created: \(title)"
            }

            return "Failed to create reminder."
        } catch {
            return "Failed to create reminder."
        }
    }

    private func clean(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
