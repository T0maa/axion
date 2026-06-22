//
//  SettingsManager.swift
//  AXION
//
//  Created by Thomas Chamard on 12/05/2026.
//

import Foundation
import Combine

final class SettingsManager: ObservableObject {
    @Published var modelPath: String {
        didSet {
            UserDefaults.standard.set(modelPath, forKey: "modelPath")
        }
    }

    init() {
        self.modelPath =
            UserDefaults.standard.string(forKey: "modelPath")
            ?? ""
    }
}
