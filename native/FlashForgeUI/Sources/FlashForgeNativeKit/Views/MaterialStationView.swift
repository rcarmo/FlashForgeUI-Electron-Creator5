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
                LazyVGrid(columns: slotColumns, spacing: 12) {
                    ForEach(station.displaySlots) { slot in
                        MaterialSlotCard(
                            slot: slot,
                            isActive: station.activeSlot == slot.slotId,
                            isLoading: station.loadingSlot == slot.slotId
                        )
                    }
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var slotColumns: [GridItem] {
        if station.displaySlots.count == 4 {
            return [
                GridItem(.flexible(minimum: 150), spacing: 12),
                GridItem(.flexible(minimum: 150), spacing: 12)
            ]
        }

        return [GridItem(.adaptive(minimum: 150), spacing: 12)]
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
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Slot \(slot.slotId)")
                    .font(.headline)
                Spacer()
                slotBadges
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(slotColor)
                    .frame(width: 16, height: 16)

                Text(slot.isEmpty ? "Empty" : slot.materialType ?? "Unknown")
                    .foregroundStyle(slot.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
            }

            HStack(spacing: 10) {
                Label(slot.isEmpty ? "Empty" : "Loaded", systemImage: slot.isEmpty ? "circle" : "checkmark.circle")
                    .foregroundStyle(.secondary)

                if let materialColor = normalizedColorLabel {
                    Label(materialColor, systemImage: "paintpalette")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .font(.caption)
        }
        .padding(12)
        .frame(minHeight: 112)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var slotBadges: some View {
        HStack(spacing: 6) {
            if isLoading {
                Label("Loading", systemImage: "arrow.triangle.2.circlepath")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.orange)
                    .help("Material is loading from this slot")
            }

            if isActive {
                Label("Active", systemImage: "checkmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.tint)
                    .help("Active material slot")
            }
        }
    }

    private var normalizedColorLabel: String? {
        guard let materialColor = slot.materialColor?.trimmingCharacters(in: .whitespacesAndNewlines),
              !slot.isEmpty,
              !materialColor.isEmpty else {
            return nil
        }

        return materialColor.hasPrefix("#") ? materialColor.uppercased() : "#\(materialColor.uppercased())"
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
