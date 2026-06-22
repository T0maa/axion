//
//  OpenURLTool.swift
//  AXION
//
//  Created by Thomas Chamard on 13/05/2026.
//

import AppKit

final class OpenURLTool: Tool {
    let name = "open_url"

    func execute(argument: String) -> String {
        let cleaned = clean(argument)
        let urlString = normalizedURL(cleaned)

        guard let url = URL(string: urlString) else {
            return "Invalid URL: \(argument)."
        }

        if openWithFirefox(url.absoluteString) {
            return "Opened URL in Firefox: \(url.absoluteString)"
        }

        return "Unable to open URL in Firefox: \(url.absoluteString)"
    }

    private func openWithFirefox(_ urlString: String) -> Bool {
        if openWithFirefoxNewTab(urlString) {
            activateFirefox()
            return true
        }

        if openWithLaunchServices(urlString) {
            activateFirefox()
            return true
        }

        return false
    }

    private func openWithFirefoxNewTab(_ urlString: String) -> Bool {
        Thread.sleep(forTimeInterval: 1.0)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Firefox", urlString]

        do {
            try process.run()
            return true
        } catch {
            return false
        }
    }

    private func openWithLaunchServices(_ urlString: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Firefox", urlString]

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func activateFirefox() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let apps = NSWorkspace.shared.runningApplications

            guard let firefox = apps.first(where: {
                $0.bundleIdentifier == "org.mozilla.firefox"
            }) else {
                return
            }

            firefox.activate(options: [
                .activateAllWindows
            ])
        }
    }

    private func clean(_ value: String) -> String {
        var cleaned = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")

        while cleaned.last == "." ||
              cleaned.last == "," ||
              cleaned.last == ";" ||
              cleaned.last == ":" {
            cleaned.removeLast()
        }

        return cleaned
    }

    private func normalizedURL(_ value: String) -> String {
        if value.hasPrefix("http://") || value.hasPrefix("https://") {
            return value
        }

        return "https://" + value
    }
}
