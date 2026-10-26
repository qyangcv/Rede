import SwiftUI
import UIKit

struct BatteryLabel: View {
    @State private var level = -1.0
    @State private var state = UIDevice.BatteryState.unknown

    var body: some View {
        HStack(spacing: 3) {
            if level >= 0 {
                Text(level, format: .percent.precision(.fractionLength(0)))
                if state == .charging || state == .full {
                    Image(systemName: "bolt.fill")
                        .imageScale(.small)
                }
                Image(systemName: symbol)
                    .imageScale(.large)
            }
        }
        .onAppear {
            UIDevice.current.isBatteryMonitoringEnabled = true
            update()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)) { _ in update() }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification)) { _ in update() }
    }

    private var symbol: String {
        switch level {
        case ..<0.13: "battery.0percent"
        case ..<0.38: "battery.25percent"
        case ..<0.63: "battery.50percent"
        case ..<0.88: "battery.75percent"
        default: "battery.100percent"
        }
    }

    private func update() {
        level = Double(UIDevice.current.batteryLevel)
        state = UIDevice.current.batteryState
    }
}
