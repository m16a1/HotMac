import SwiftUI
import AppKit

/// The About screen: the bundled app icon, the name, and the version, opened
/// from the menu into its own window.
struct AboutView: View {
    private enum Metrics {
        /// 256 pt is 512 px on a Retina display. The `.icns` carries up to
        /// 1024 px, so the icon stays sharp.
        static let iconSize: CGFloat = 256
        /// Apple draws macOS icons on a superellipse whose corner radius is
        /// about 22.37% of the edge; this uses half of that, which reads
        /// subtler on the full-bleed square source image.
        static let iconCornerRadius: CGFloat = iconSize * 0.11185
        static let fallbackIconSize: CGFloat = 128
        static let windowWidth: CGFloat = 360
        static let padding: CGFloat = 32
        static let spacing: CGFloat = 12
    }

    private enum InfoKey {
        static let name = "CFBundleName"
        static let shortVersion = "CFBundleShortVersionString"
        static let buildVersion = "CFBundleVersion"
    }

    private enum Strings {
        static let fallbackName = "HotMac"
        static let tagline = "The hottest sensor, right in the menu bar"
    }

    var body: some View {
        VStack(spacing: Metrics.spacing) {
            icon
            Text(name)
                .font(.title2)
                .fontWeight(.semibold)
            Text(version)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(Strings.tagline)
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, Metrics.spacing)
        }
        .padding(Metrics.padding)
        .frame(width: Metrics.windowWidth)
    }

    @ViewBuilder private var icon: some View {
        if let image = Self.appIcon {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: Metrics.iconSize, height: Metrics.iconSize)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: Metrics.iconCornerRadius,
                        style: .continuous
                    )
                )
        } else {
            Image(systemName: "thermometer.medium")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
                .frame(width: Metrics.fallbackIconSize, height: Metrics.fallbackIconSize)
        }
    }

    private var name: String {
        Self.string(for: InfoKey.name) ?? Strings.fallbackName
    }

    private var version: String {
        let short = Self.string(for: InfoKey.shortVersion)
        let build = Self.string(for: InfoKey.buildVersion)
        return switch (short, build) {
        case let (short?, build?): "Version \(short) (\(build))"
        case let (short?, nil): "Version \(short)"
        default: ""
        }
    }

    private static func string(for key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }

    /// The `.icns` `build.py` renders from `AppIcon.png`, or nil when that
    /// source image was absent and the bundle was left on the generic icon.
    private static var appIcon: NSImage? {
        Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
            .flatMap(NSImage.init(contentsOf:))
    }
}
