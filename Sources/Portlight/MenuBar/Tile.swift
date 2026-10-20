import SwiftUI

/// A Control Center–style rounded module.
struct Tile<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// The round toggle used at the leading edge of a tile.
struct TileToggle: View {
    let systemImage: String
    let isOn: Bool

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(isOn ? Color.white : Color.primary)
            .frame(width: 30, height: 30)
            .background(isOn ? Color.accentColor : Color.primary.opacity(0.1), in: Circle())
    }
}
