//
//  LlamaServerManager.swift
//  AXION
//
//  Created by Thomas Chamard on 12/05/2026.
//

import Foundation
import Combine

final class LlamaServerManager: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var isReady = false
    @Published private(set) var errorMessage: String?

    private var process: Process?

    func start(settings: SettingsManager) {
        guard process == nil || process?.isRunning == false else {
            return
        }

        guard let bundledLlamaServerPath = Bundle.main.path(forResource: "llama-server", ofType: nil) else {
            errorMessage = "llama-server not found in app bundle"
            return
        }

        let llamaServerPath = bundledLlamaServerPath

        guard FileManager.default.fileExists(atPath: llamaServerPath) else {
            errorMessage = "llama-server file does not exist at \(llamaServerPath)"
            return
        }

        guard FileManager.default.isExecutableFile(atPath: llamaServerPath) else {
            errorMessage = "llama-server is not executable at \(llamaServerPath)"
            return
        }

        guard FileManager.default.fileExists(atPath: settings.modelPath) else {
            errorMessage = "Model file not found"
            return
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: llamaServerPath)
        process.arguments = [
            "-m", settings.modelPath,
            "--port", "8080",
            "-c", "4096",
            "-ngl", "99"
        ]

        do {
            try process.run()
            self.process = process
            self.isRunning = true
            self.errorMessage = nil

            Task {
                await waitUntilReady()
            }
        } catch {
            self.isRunning = false
            self.isReady = false
            self.errorMessage = "Failed to start llama-server"
            print("Failed to start llama-server: \(error)")
        }
    }

    func stop() {
        guard let process else {
            return
        }
        
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        
        self.process = nil
        isRunning = false
        isReady = false
    }
    
    deinit {
        stop()
    }

    private func waitUntilReady() async {
        for _ in 0..<60 {
            if await checkHealth() {
                await MainActor.run {
                    self.isReady = true
                }
                return
            }

            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        await MainActor.run {
            self.isReady = false
        }
    }

    private func checkHealth() async -> Bool {
        guard let url = URL(string: "http://localhost:8080/health") else {
            return false
        }

        do {
            let (_, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse else {
                return false
            }

            return httpResponse.statusCode == 200
        } catch {
            return false
        }
    }
}
