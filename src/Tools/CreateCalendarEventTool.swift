//
//  CreateCalendarEventTool.swift
//  AXION
//
//  Created by Thomas Chamard on 22/06/2026.
//

import Foundation

final class CreateCalendarEventTool: Tool {
    let name = "create_calendar_event"

    func execute(argument: String) -> String {
        let parts = argument.split(separator: "|", maxSplits: 2).map(String.init)

        guard parts.count == 3 else {
            return "Invalid calendar event arguments. Expected title|start|end."
        }

        let title = clean(parts[0])
        let start = clean(parts[1])
        let end = clean(parts[2])

        guard !title.isEmpty, !start.isEmpty, !end.isEmpty else {
            return "Missing calendar event title, start, or end."
        }

        let script = """
        tell application "Calendar"
            tell calendar "Calendar"
                set startDate to date "\(escape(start))"
                set endDate to date "\(escape(end))"
                make new event with properties {summary:"\(escape(title))", start date:startDate, end date:endDate}
            end tell
        end tell
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                return "Calendar event created: \(title)"
            }

            return "Failed to create calendar event."
        } catch {
            return "Failed to create calendar event."
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
