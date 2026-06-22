//
//  ListProcessesTool.swift
//  AXION
//
//  Created by Thomas Chamard on 22/06/2026.
//

import Foundation

final class ListProcessesTool: Tool {
    let name = "list_processes"

    func execute(argument: String) -> String {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid,comm", "-r"]
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                return "Failed to list processes."
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            let lines = output
                .split(separator: "\n")
                .prefix(40)
                .map(String.init)

            return "Running processes:\n" + lines.joined(separator: "\n")
        } catch {
            return "Failed to list processes."
        }
    }
}
