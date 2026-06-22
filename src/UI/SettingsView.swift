//
//  SettingsView.swift
//  AXION
//
//  Created by Thomas Chamard on 12/05/2026.
//

import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("AXON Settings")
                .font(.title2)
                .bold()

            Text("Model path")
                .font(.headline)

            HStack {
                TextField("Path to GGUF model", text: $settings.modelPath)
                    .textFieldStyle(.roundedBorder)

                Button("Browse...") {
                    selectModelFile()
                }
            }

            HStack {
                Spacer()

                Button("Done") {
                    dismiss()
                }
            }
        }
        .padding()
        .frame(width: 520, height: 220)
    }
    
    private func selectModelFile() {
        let panel = NSOpenPanel()

        panel.title = "Select GGUF model"
        panel.allowedContentTypes = []
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        if panel.runModal() == .OK {
            settings.modelPath = panel.url?.path ?? ""
        }
    }
}
