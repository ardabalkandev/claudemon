import Foundation

/// How the menu-bar label presents the live session usage. Persisted by
/// `UsageStore` as a raw string and chosen by the user in the settings footer.
public enum MenuBarDisplayMode: String, CaseIterable, Identifiable {
    case iconAndText
    case textOnly
    case iconOnly

    public var id: String { rawValue }

    /// Human-readable name for the settings Picker.
    public var label: String {
        switch self {
        case .iconAndText: return "Icon + Text"
        case .textOnly: return "Text only"
        case .iconOnly: return "Icon only"
        }
    }
}
