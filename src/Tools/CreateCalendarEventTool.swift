//
//  CreateCalendarEventTool.swift
//  AXION
//
//  Created by Thomas Chamard on 22/06/2026.
//

import Foundation

final class CreateCalendarEventTool: Tool {
    let name = "create_calendar_event"

    func execute(argument: String) -> ToolExecutionResult {
        let parts = argument.split(separator: "|", maxSplits: 2).map(String.init)

        guard parts.count == 3 else {
            return .failure(title: "Invalid calendar event arguments", detail: "Expected title|start|end.")
        }

        let title = clean(parts[0])
        let start = clean(parts[1])
        let end = clean(parts[2])

        guard !title.isEmpty, !start.isEmpty, !end.isEmpty else {
            return .failure(title: "Missing calendar event title, start, or end")
        }

        let startDateAssignment = appleScriptDateAssignment(
            variableName: "startDate",
            rawValue: start
        )

        let endDateAssignment = appleScriptDateAssignment(
            variableName: "endDate",
            rawValue: end
        )

        let script = """
        tell application "Calendar"
            set targetCalendar to first calendar whose writable is true
            tell targetCalendar
                \(startDateAssignment)
                \(endDateAssignment)
                make new event with properties {summary:"\(escape(title))", start date:startDate, end date:endDate}
            end tell
        end tell
        """

        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            let output = String(
                data: outputPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""

            let errorOutput = String(
                data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""

            if process.terminationStatus == 0 {
                let detail = "\(title) — \(start) to \(end)"

                return .success(
                    title: "Calendar event created",
                    detail: detail,
                    rawOutput: output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? detail : output
                )
            }

            let cleanError = errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallbackDetail = "Missing Calendar or Automation permission, invalid date format, or no writable calendar found. Start: \(start), End: \(end)"

            return .failure(
                title: "Failed to create calendar event",
                detail: cleanError.isEmpty ? fallbackDetail : cleanError,
                displayStyle: .textBlock
            )
        } catch {
            return .failure(
                title: "Failed to create calendar event",
                detail: error.localizedDescription,
                displayStyle: .textBlock
            )
        }
    }

    private func appleScriptDateAssignment(variableName: String, rawValue: String) -> String {
        if let date = parseRelativeDate(rawValue) {
            let seconds = Int(date.timeIntervalSinceNow.rounded())
            return "set \(variableName) to (current date) + \(seconds)"
        }

        return "set \(variableName) to date \"\(escape(rawValue))\""
    }

    private func parseRelativeDate(_ rawValue: String) -> Date? {
        let lowercasedValue = rawValue
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let dayOffset: Int

        if lowercasedValue.contains("tomorrow") {
            dayOffset = 1
        } else if lowercasedValue.contains("today") {
            dayOffset = 0
        } else {
            return nil
        }

        let pattern = #"(\d{1,2})(?::(\d{2}))?\s*(am|pm)?"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }

        let range = NSRange(lowercasedValue.startIndex..<lowercasedValue.endIndex, in: lowercasedValue)

        guard let match = regex.firstMatch(in: lowercasedValue, options: [], range: range) else {
            return nil
        }

        func group(_ index: Int) -> String? {
            let nsRange = match.range(at: index)

            guard nsRange.location != NSNotFound,
                  let range = Range(nsRange, in: lowercasedValue) else {
                return nil
            }

            return String(lowercasedValue[range])
        }

        guard var hour = Int(group(1) ?? "") else {
            return nil
        }

        let minute = Int(group(2) ?? "") ?? 0
        let meridiem = group(3)?.lowercased()

        if meridiem == "pm", hour < 12 {
            hour += 12
        }

        if meridiem == "am", hour == 12 {
            hour = 0
        }

        guard hour >= 0, hour <= 23, minute >= 0, minute <= 59 else {
            return nil
        }

        let calendar = Calendar.current
        let baseDate = calendar.date(
            byAdding: .day,
            value: dayOffset,
            to: calendar.startOfDay(for: Date())
        ) ?? Date()

        var components = calendar.dateComponents([.year, .month, .day], from: baseDate)
        components.hour = hour
        components.minute = minute
        components.second = 0

        return calendar.date(from: components)
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
