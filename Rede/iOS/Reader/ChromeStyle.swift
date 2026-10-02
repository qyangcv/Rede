import SwiftUI

struct ChromeStyle: ShapeStyle {
    enum Level { case panel, card }

    let background: BackgroundColor
    let level: Level

    func resolve(in environment: EnvironmentValues) -> Color.Resolved {
        let dark = environment.colorScheme == .dark
        let amount = switch level {
        case .panel: dark ? 0.04 : 0.2
        case .card: dark ? 0.10 : 0.4
        }
        return background.swatch(for: environment.colorScheme)
            .mix(with: .white, by: amount)
            .resolve(in: environment)
    }
}
