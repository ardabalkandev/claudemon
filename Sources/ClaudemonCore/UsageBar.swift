import SwiftUI

/// A compact, geometry-driven usage bar shared by the floating mini-window and
/// the WidgetKit widget so both surfaces fill identically.
///
/// Unlike `ProgressView(.linear)`, this guarantees the fill width tracks the
/// percentage exactly (0–100, clamped). The fill color uses the shared
/// `UsageColor` thresholds, matching the session ring.
///
/// Two fill styles:
/// - Default: a capsule fill with a small visible minimum, so low values like
///   2% still read as "some usage" at a glance.
/// - Precise (`precise: true`): a straight-edged fill at the exact
///   proportional width, clipped by the rounded track — no minimum — so 2%
///   and 8% are visually distinct.
public struct UsageBar: View {
    private let percent: Int
    private let height: CGFloat
    private let precise: Bool

    public init(percent: Int, height: CGFloat = 6, precise: Bool = false) {
        self.percent = percent
        self.height = height
        self.precise = precise
    }

    public var body: some View {
        let clamped = max(0, min(100, percent))
        GeometryReader { geo in
            let fullWidth = geo.size.width
            let fraction = CGFloat(clamped) / 100.0
            // Non-precise keeps a small visible sliver for any non-zero value
            // so e.g. 2% does not look empty; precise draws the exact width.
            let minVisible: CGFloat = (!precise && clamped > 0) ? height : 0
            let fillWidth = max(minVisible, fullWidth * fraction)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.15))
                fillShape
                    .fill(UsageColor.color(for: clamped))
                    .frame(width: min(fullWidth, fillWidth))
            }
            // Round only the track's outline: the precise fill keeps its
            // straight trailing edge, trimmed at the capsule ends.
            .clipShape(Capsule())
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    private var fillShape: AnyShape {
        precise ? AnyShape(Rectangle()) : AnyShape(Capsule())
    }
}

/// The vertical counterpart of `UsageBar`: same track/fill/color language and
/// fill styles, but the fill grows bottom-up. Used by the menu-bar bar-graph
/// label's vertical layout.
public struct VerticalUsageBar: View {
    private let percent: Int
    private let width: CGFloat
    private let precise: Bool

    public init(percent: Int, width: CGFloat = 6, precise: Bool = false) {
        self.percent = percent
        self.width = width
        self.precise = precise
    }

    public var body: some View {
        let clamped = max(0, min(100, percent))
        GeometryReader { geo in
            let fullHeight = geo.size.height
            // Same readability rule as the horizontal bar: a small visible
            // sliver in the default style, the exact height in precise style.
            let fraction = CGFloat(clamped) / 100.0
            let minVisible: CGFloat = (!precise && clamped > 0) ? width : 0
            let fillHeight = max(minVisible, fullHeight * fraction)

            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(Color.primary.opacity(0.15))
                fillShape
                    .fill(UsageColor.color(for: clamped))
                    .frame(height: min(fullHeight, fillHeight))
            }
            .clipShape(Capsule())
        }
        .frame(width: width)
        .accessibilityHidden(true)
    }

    private var fillShape: AnyShape {
        precise ? AnyShape(Rectangle()) : AnyShape(Capsule())
    }
}
