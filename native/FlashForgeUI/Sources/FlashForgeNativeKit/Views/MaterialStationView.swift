import SwiftUI

public struct MaterialStationView: View {
    private let station: MaterialStationStatus

    public init(station: MaterialStationStatus) {
        self.station = station
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Material Station", systemImage: "square.grid.2x2")
                    .font(.title2.weight(.semibold))

                Spacer()

                Text(station.overallStatus.rawValue.capitalized)
                    .foregroundStyle(statusColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(station.statusSummary)
                    .foregroundStyle(.secondary)

                if let activeSlotSummary = station.activeSlotSummary {
                    Text(activeSlotSummary)
                        .foregroundStyle(.secondary)
                }
            }

            if !station.displaySlots.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    ForEach(station.displaySlots) { slot in
                        MaterialSlotCard(
                            slot: slot,
                            isActive: station.activeSlot == slot.slotId
                        )
                    }
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var statusColor: Color {
        switch station.overallStatus {
        case .error:
            return Color.red
        case .disconnected:
            return Color.orange
        case .ready, .warming:
            return station.connected ? Color.secondary : Color.orange
        }
    }
}

private struct MaterialSlotCard: View {
    let slot: MaterialStationSlot
    let isActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Slot \(slot.slotId)")
                    .font(.headline)
                Spacer()
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                }
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(slotColor)
                    .frame(width: 16, height: 16)

                Text(slot.isEmpty ? "Empty" : slot.materialType ?? "Unknown")
                    .foregroundStyle(slot.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private var slotColor: Color {
        guard let materialColor = slot.materialColor, !slot.isEmpty else {
            return Color.secondary.opacity(0.35)
        }

        return Color(hexString: materialColor) ?? Color.secondary.opacity(0.35)
    }
}

private extension Color {
    init?(hexString: String) {
        let cleaned = hexString
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))

        guard cleaned.count == 6,
              let value = Int(cleaned, radix: 16) else {
            return nil
        }

        let red = Double((value >> 16) & 0xff) / 255
        let green = Double((value >> 8) & 0xff) / 255
        let blue = Double(value & 0xff) / 255
        self.init(red: red, green: green, blue: blue)
    }
}
