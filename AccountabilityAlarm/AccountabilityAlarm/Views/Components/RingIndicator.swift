import SwiftUI

struct RingIndicator: View {
    let currentRing: EscalationRing

    var body: some View {
        HStack(spacing: 6) {
            ForEach(EscalationRing.allCases, id: \.rawValue) { ring in
                Circle()
                    .fill(ring.rawValue <= currentRing.rawValue ? ringColor(ring) : Color(.systemGray4))
                    .frame(width: 8, height: 8)
            }
            Text(currentRing.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func ringColor(_ ring: EscalationRing) -> Color {
        switch ring {
        case .nudge: .green
        case .math: .yellow
        case .mirror: .orange
        case .preview: .red
        }
    }
}
