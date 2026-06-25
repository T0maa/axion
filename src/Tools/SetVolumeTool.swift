//
//  SetVolumeTool.swift
//  AXION
//
//  Created by Thomas Chamard on 22/06/2026.
//

import Foundation

final class SetVolumeTool: Tool {
    let name = "set_volume"

    func execute(argument: String) -> ToolExecutionResult {
        let cleaned = argument.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let volume = Int(cleaned), volume >= 0, volume <= 100 else {
            return .failure(title: "Invalid volume", detail: "Expected a number between 0 and 100.")
        }

        let script = "set volume output volume \(volume)"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
                ? .success(title: "Volume set", detail: "\(volume)%")
                : .failure(title: "Failed to set volume")
        } catch {
            return .failure(title: "Failed to set volume")
        }
    }
}
