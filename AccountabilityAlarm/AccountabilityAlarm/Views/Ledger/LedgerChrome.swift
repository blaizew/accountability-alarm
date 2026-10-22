import SwiftUI

// Shared chrome bits: top bar, title block, tab bar.

struct LTopBar: View {
    let left: String
    var right: String = ""
    var leftColor: Color = L.Palette.muted
    var rightColor: Color = L.Palette.dim
    var onRight: (() -> Void)? = nil
    var trailing: AnyView? = nil

    var body: some View {
        HStack(spacing: 12) {
            Text(left)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .kicker(leftColor)

            if !right.isEmpty {
                Button {
                    onRight?()
                } label: {
                    Text(right)
                        .kicker(rightColor)
                }
                .buttonStyle(.plain)
            }

            if let trailing { trailing }
        }
        .padding(.horizontal, L.Space.pageH)
        .padding(.vertical, 8)
        .background(L.Palette.bg)
        .overlay(alignment: .bottom) { L.Palette.hair.frame(height: 1) }
    }
}

struct LTitle: View {
    let kicker: String
    let title: String
    var count: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(kicker).kicker()
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(L.Mono.font(26, weight: .medium))
                    .tracking(-0.4)
                    .foregroundStyle(L.Palette.fg)
                Spacer()
                if let count {
                    Text("[\(count)]")
                        .font(L.Mono.font(11))
                        .foregroundStyle(L.Palette.muted)
                }
            }
        }
        .padding(.horizontal, L.Space.pageH)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }
}

enum LTab: String { case alarms, history, debug }

struct LTabBar: View {
    @Binding var active: LTab

    var body: some View {
        HStack {
            ForEach([LTab.alarms, LTab.history, LTab.debug], id: \.self) { tab in
                let on = tab == active
                Button {
                    active = tab
                } label: {
                    HStack(spacing: 6) {
                        if on { L.Dot(size: 5, color: L.Palette.fg) }
                        Text(tab.rawValue.capitalized)
                            .kicker(on ? L.Palette.fg : L.Palette.dim)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 50)
        .background(L.Palette.bg2)
        .overlay(alignment: .top) { L.Palette.hair.frame(height: 1) }
    }
}
