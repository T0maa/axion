//
//  SearchInSpotlightTool.swift
//  AXION
//
//  Created by Thomas Chamard on 22/06/2026.
//

import Foundation

final class SearchInSpotlightTool: Tool {
    let name = "search_in_spotlight"

    func execute(argument: String) async -> ToolExecutionResult {
        let query = clean(argument)

        guard !query.isEmpty else {
            return .failure(title: "Missing Spotlight search query")
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
                return .failure(title: "Spotlight search failed")
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            let results = output
                .split(separator: "\n")
                .prefix(20)
                .map(String.init)

            if results.isEmpty {
                return .neutral(title: "No Spotlight results found", detail: query)
            }

            return .success(title: "Spotlight results", detail: query, rawOutput: "Spotlight results:\n" + results.joined(separator: "\n"))
        } catch {
            return .failure(title: "Spotlight search failed")
        }
    }

    private func clean(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
    }
}
