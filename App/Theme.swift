import SwiftUI

/// One place for the app's small design vocabulary — reuses barry-iphone's
/// exact accent purple and visual language, adapted to point-guard's own
/// status vocabulary ("ok"/"stuck"/"conflicted", not "running"/"pending"/...).
enum Theme {
    /// Barry purple — matches the accent used across barry-iphone and barry.works.
    static let accent = Color(red: 0.655, green: 0.545, blue: 0.980)

    static var accentSoft: Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0.173, green: 0.141, blue: 0.251, alpha: 1) // #2c2440
                : UIColor(red: 0.937, green: 0.914, blue: 0.984, alpha: 1) // #efe9fb
        })
    }

    /// point-guard's book status vocabulary: ok → green, stuck → orange,
    /// conflicted → red. Any unrecognized value falls back to neutral gray
    /// rather than guessing.
    static func statusColor(_ status: String) -> Color {
        switch status {
        case "ok": return .green
        case "stuck": return .orange
        case "conflicted": return .red
        default: return Color(.systemGray3)
        }
    }

    static func statusLabel(_ status: String) -> String {
        switch status {
        case "ok": return "OK"
        case "stuck": return "Stuck"
        case "conflicted": return "Conflicted"
        default: return status.capitalized
        }
    }
}

/// Small colored dot used for session status.
struct StatusDot: View {
    let status: String
    var body: some View {
        Circle()
            .fill(Theme.statusColor(status))
            .frame(width: 8, height: 8)
    }
}
