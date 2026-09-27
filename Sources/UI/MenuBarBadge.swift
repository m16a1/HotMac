import SwiftUI
import AppKit
import Sensors

/// The menu bar item: plain text while the machine is cool, and a filled
/// capsule once the temperature climbs into a band worth flagging.
///
/// `MenuBarExtra` draws its label as a monochrome template image, so a tint
/// applied to the `Text` is discarded and the system recolors what is left.
/// Keeping a fill therefore means drawing the label here and handing the result
/// over as a non-template image, which the system leaves alone.
struct MenuBarBadge: View {
    let title: String
    let level: TemperatureLevel?

    var body: some View {
        if let level, let badge = Self.render(title: title, level: level) {
            Image(nsImage: badge)
                .renderingMode(.original)
        } else {
            Text(title)
                .monospacedDigit()
        }
    }

    private enum Metrics {
        static let fontSize: CGFloat = 13
        static let weight: Font.Weight = .medium
        static let horizontalPadding: CGFloat = 6
        static let verticalPadding: CGFloat = 1
        static let fallbackScale: CGFloat = 2

        /// Dark text on every fill. Measured against the system palette, black
        /// clears 5:1 on the yellow, orange and red, where white on red would
        /// sit near 3.4:1.
        static let textColor: Color = .black
    }

    /// The fill a band gets. `normal` gets none, which is what leaves the item
    /// as plain text at the temperatures a machine at rest reads.
    private static func fill(for level: TemperatureLevel) -> Color? {
        switch level {
        case .normal: nil
        case .warm: .yellow
        case .hot: .orange
        case .critical: .red
        }
    }

    @MainActor
    private static func render(title: String, level: TemperatureLevel) -> NSImage? {
        guard let fill = fill(for: level) else { return nil }
        let renderer = ImageRenderer(content: badge(title: title, fill: fill))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? Metrics.fallbackScale
        guard let image = renderer.nsImage else { return nil }
        image.isTemplate = false
        return image
    }

    /// The label as it is drawn into the image. Kept apart from `body` so that
    /// rendering never recurses back into the view it is rendering.
    private static func badge(title: String, fill: Color) -> some View {
        Text(title)
            .font(.system(size: Metrics.fontSize, weight: Metrics.weight))
            .monospacedDigit()
            .foregroundStyle(Metrics.textColor)
            .padding(.horizontal, Metrics.horizontalPadding)
            .padding(.vertical, Metrics.verticalPadding)
            .background(Capsule().fill(fill))
    }
}
