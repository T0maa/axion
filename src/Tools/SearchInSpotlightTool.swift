//
//  SearchInSpotlightTool.swift
//  AXION
//
//  Created by Thomas Chamard on 22/06/2026.
//

import Foundation

final class SearchInSpotlightTool: Tool {
    let name = "search_in_spotlight"

    func execute(argument: String) -> String {
        let query = clean(argument)

        guard !query.isEmpty else {
            return "Missing Spotlight search query."
        }

        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = [query]
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                return "Spotlight search failed."
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            let results = output
                .split(separator: "\n")
                .prefix(20)
                .map(String.init)

            if results.isEmpty {
                return "No Spotlight results found for: \(query)"
            }

            return "Spotlight results:\n" + results.joined(separator: "\n")
        } catch {
            return "Spotlight search failed."
        }
    }

    private func clean(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
    }
}
