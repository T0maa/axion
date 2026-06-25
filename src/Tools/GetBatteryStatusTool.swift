//
//  GetBatteryStatusTool.swift
//  AXION
//
//  Created by Thomas Chamard on 22/06/2026.
//

import Foundation
import IOKit.ps

final class GetBatteryStatusTool: Tool {
    let name = "get_battery_status"

    func execute(argument: String) -> ToolExecutionResult {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              let source = sources.first,
              let description = IOPSGetPowerSourceDescription(snapshot, source)?
                  .takeUnretainedValue() as? [String: Any] else {
            return .failure(title: "Battery status unavailable")
        }

        let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
        let max = description[kIOPSMaxCapacityKey] as? Int ?? 100
        let percent = max > 0 ? Int((Double(current) / Double(max)) * 100.0) : 0
        let charging = description[kIOPSIsChargingKey] as? Bool ?? false
        let powerSource = description[kIOPSPowerSourceStateKey] as? String ?? "Unknown"

        return .success(
            title: "Battery status",
            detail: "\(percent)%",
            rawOutput: "Battery status:\nLevel: \(percent)%\nCharging: \(charging ? "yes" : "no")\nPower source: \(powerSource)"
        )
    }
}
