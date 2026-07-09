import SwiftUI

/// How the menu-bar label presents the live session usage. Persisted by
/// `UsageStore` as a raw string and chosen by the user in the settings footer.
public enum MenuBarDisplayMode: String, CaseIterable, Identifiable {
    case iconAndText
    case textOnly
    case iconOnly
    case bars

    public var id: String { rawValue }

    /// Human-readable name for the settings Picker.
    public var label: String {
        switch self {
        case .iconAndText: return "Icon + Text"
        case .textOnly: return "Text only"
        case .iconOnly: return "Icon only"
        case .bars: return "Bar graph"
        }
    }
}

/// Fixed-size bar-graph content for the menu-bar label: the session limit as a
/// bar, optionally the weekly (all models) limit as a second bar, and
/// optionally the percent value(s) beside the bars. Bars use the shared
/// `UsageColor` thresholds so they match the in-app usage bars.
///
/// The menu bar renders live SwiftUI label views as template (monochrome)
/// content, so the app rasterizes this view into a non-template `NSImage` —
/// which is why every dimension here is fixed: the rendered image must have a
/// stable size so the menu-bar item never jitters as values change.
public struct MenuBarBarsView: View {

    /// Everything that affects the rendered pixels, grouped so the app can
    /// compare configurations cheaply when deciding whether to re-render.
    public struct Configuration: Equatable {
        public var sessionPercent: Int
        /// Weekly (all models) percent; nil renders the session bar only.
        public var weekPercent: Int?
        public var showsPercent: Bool
        public var isVertical: Bool
        /// Exact straight-edged fills instead of the min-sliver capsule fill.
        public var preciseFill: Bool
        /// Horizontal bars at half the standard width. Ignored in vertical
        /// mode, where the bar length is the menu-bar content height.
        public var halfWidthBars: Bool

        public init(sessionPercent: Int, weekPercent: Int?,
                    showsPercent: Bool, isVertical: Bool,
                    preciseFill: Bool = false,
                    halfWidthBars: Bool = false) {
            self.sessionPercent = sessionPercent
            self.weekPercent = weekPercent
            self.showsPercent = showsPercent
            self.isVertical = isVertical
            self.preciseFill = preciseFill
            self.halfWidthBars = halfWidthBars
        }
    }

    private let config: Configuration

    /// The menu bar's usable content height.
    private static let contentHeight: CGFloat = 16
    /// The standard "set width" of a horizontal bar (a vertical bar's length
    /// is `contentHeight`), independent of the percentage shown.
    private static let fullBarLength: CGFloat = 40

    /// The horizontal bar width for this configuration.
    private var barLength: CGFloat {
        config.halfWidthBars ? Self.fullBarLength / 2 : Self.fullBarLength
    }

    public init(_ config: Configuration) {
        self.config = config
    }

    public var body: some View {
        HStack(spacing: 4) {
            if config.isVertical {
                verticalBars
            } else {
                horizontalBars
            }
            if config.showsPercent {
                percentColumn
            }
        }
        .frame(height: Self.contentHeight)
        .accessibilityHidden(true) // the label view supplies the a11y string
    }

    // MARK: - Bars

    private var horizontalBars: some View {
        VStack(alignment: .leading, spacing: 2) {
            UsageBar(percent: config.sessionPercent, height: barThickness,
                     precise: config.preciseFill)
                .frame(width: barLength)
            if let week = config.weekPercent {
                UsageBar(percent: week, height: barThickness,
                         precise: config.preciseFill)
                    .frame(width: barLength)
            }
        }
    }

    private var verticalBars: some View {
        HStack(spacing: 3) {
            VerticalUsageBar(percent: config.sessionPercent, width: barThickness,
                             precise: config.preciseFill)
                .frame(height: Self.contentHeight)
            if let week = config.weekPercent {
                VerticalUsageBar(percent: week, width: barThickness,
                                 precise: config.preciseFill)
                    .frame(height: Self.contentHeight)
            }
        }
    }

    /// Single bars get a little more presence; paired bars slim down so two
    /// stacked horizontal bars still fit the menu-bar content height.
    private var barThickness: CGFloat {
        config.weekPercent == nil ? 7 : 6
    }

    // MARK: - Percent labels

    @ViewBuilder
    private var percentColumn: some View {
        if let week = config.weekPercent {
            // Two bars: both percents, vertically stacked in a smaller font.
            // Order matches the bars (session first, week second).
            VStack(alignment: .leading, spacing: 0) {
                percentText(config.sessionPercent, size: 8)
                percentText(week, size: 8)
            }
            .frame(width: 25, alignment: .leading)
        } else {
            percentText(config.sessionPercent, size: 11)
                .frame(width: 33, alignment: .leading)
        }
    }

    // Percent column widths are sized to the worst case ("100%": 24.1pt at 8pt,
    // 32.2pt at 11pt, monospaced digits) so the item width never jitters; the
    // leading alignment means shorter values leave their slack on the right.

    /// Fixed-width, monospaced-digit percent so the image width is stable.
    private func percentText(_ percent: Int, size: CGFloat) -> some View {
        Text("\(percent)%")
            .font(.system(size: size, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(.primary)
            .lineLimit(1)
    }
}
