//
//  SetVolumeTool.swift
//  AXION
//
//  Created by Thomas Chamard on 22/06/2026.
//

import Foundation

final class SetVolumeTool: Tool {
    let name = "set_volume"

    func execute(argument: String) -> String {
        let cleaned = argument.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let volume = Int(cleaned), volume >= 0, volume <= 100 else {
            return "Invalid volume. Expected a number between 0 and 100."
        }

        let script = "set volume output volume \(volume)"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
                ? "Volume set to \(volume)%."
                : "Failed to set volume."
        } catch {
            return "Failed to set volume."
        }
    }
}
