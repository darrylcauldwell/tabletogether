import SwiftUI
import Charts

/// A simple donut chart showing protein/carbs/fat percentages
/// Uses soft colors from the theme for a calm, non-clinical appearance
struct MacroDistributionRing: View {
    let distribution: MacroDistribution

    private var macroData: [MacroSegment] {
        guard distribution.hasData else {
            // Show placeholder when no data
            return [
                MacroSegment(name: "No data", value: 100, color: Color.slateGray.opacity(0.3))
            ]
        }

        return [
            MacroSegment(name: "Protein", value: distribution.proteinPercent, color: Color.macroProtein),
            MacroSegment(name: "Carbs", value: distribution.carbsPercent, color: Color.macroCarbs),
            MacroSegment(name: "Fat", value: distribution.fatPercent, color: Color.macroFat)
        ]
    }

    var body: some View {
        VStack(spacing: 8) {
            // Donut chart
            Chart(macroData) { segment in
                SectorMark(
                    angle: .value("Percent", segment.value),
                    innerRadius: .ratio(0.6),
                    angularInset: 1.5
                )
                .foregroundStyle(segment.color)
                .cornerRadius(3)
            }
            .chartLegend(.hidden)
            .frame(width: 80, height: 80)

            // Legend below
            if distribution.hasData {
                MacroLegend(distribution: distribution)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(macroAccessibilityLabel)
    }

    private var macroAccessibilityLabel: String {
        guard distribution.hasData else {
            return "Macro distribution: No data available"
        }
        return "Macro distribution: \(Int(distribution.proteinPercent))% protein, \(Int(distribution.carbsPercent))% carbs, \(Int(distribution.fatPercent))% fat"
    }
}

// MARK: - Supporting Types

struct MacroSegment: Identifiable {
    let id = UUID()
    let name: String
    let value: Double
    let color: Color
}

// MARK: - Macro Legend

struct MacroLegend: View {
    let distribution: MacroDistribution

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            MacroLegendItem(
                color: Color.macroProtein,
                label: "P",
                percent: Int(distribution.proteinPercent)
            )

            MacroLegendItem(
                color: Color.macroCarbs,
                label: "C",
                percent: Int(distribution.carbsPercent)
            )

            MacroLegendItem(
                color: Color.macroFat,
                label: "F",
                percent: Int(distribution.fatPercent)
            )
        }
    }
}

struct MacroLegendItem: View {
    let color: Color
    let label: String
    let percent: Int

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)

            Text("\(label): \(percent)%")
                .font(.caption2)
                .foregroundStyle(Color.slateGray)
        }
    }
}

// MARK: - Macro Colors Extension

extension Color {
    /// Soft sage-tinted green for protein
    static let macroProtein = Color(red: 0.55, green: 0.75, blue: 0.65)

    /// Soft warm tone for carbs
    static let macroCarbs = Color(red: 0.85, green: 0.75, blue: 0.55)

    /// Soft cool tone for fat
    static let macroFat = Color(red: 0.65, green: 0.75, blue: 0.85)
}

// MARK: - Standalone Ring View (for reuse)

/// A more detailed macro ring view with percentages displayed inside
struct DetailedMacroRing: View {
    let distribution: MacroDistribution
    let size: CGFloat

    private var macroData: [MacroSegment] {
        guard distribution.hasData else {
            return [
                MacroSegment(name: "No data", value: 100, color: Color.slateGray.opacity(0.3))
            ]
        }

        return [
            MacroSegment(name: "Protein", value: distribution.proteinPercent, color: Color.macroProtein),
            MacroSegment(name: "Carbs", value: distribution.carbsPercent, color: Color.macroCarbs),
            MacroSegment(name: "Fat", value: distribution.fatPercent, color: Color.macroFat)
        ]
    }

    var body: some View {
        ZStack {
            // Donut chart
            Chart(macroData) { segment in
                SectorMark(
                    angle: .value("Percent", segment.value),
                    innerRadius: .ratio(0.65),
                    angularInset: 2
                )
                .foregroundStyle(segment.color)
                .cornerRadius(4)
            }
            .chartLegend(.hidden)

            // Center content
            if distribution.hasData {
                VStack(spacing: 0) {
                    Text("Macros")
                        .font(.caption2)
                        .foregroundStyle(Color.slateGray)
                }
            } else {
                Text("--")
                    .font(.caption)
                    .foregroundStyle(Color.slateGray)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Full Macro Ring Card

/// A card-style component with the ring and full legend
struct MacroRingCard: View {
    let distribution: MacroDistribution
    let title: String

    var body: some View {
        VStack(spacing: 16) {
            if !title.isEmpty {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(Color.charcoal)
            }

            HStack(spacing: 24) {
                DetailedMacroRing(distribution: distribution, size: 100)

                VStack(alignment: .leading, spacing: 8) {
                    FullMacroLegendItem(
                        color: Color.macroProtein,
                        name: "Protein",
                        percent: Int(distribution.proteinPercent)
                    )

                    FullMacroLegendItem(
                        color: Color.macroCarbs,
                        name: "Carbs",
                        percent: Int(distribution.carbsPercent)
                    )

                    FullMacroLegendItem(
                        color: Color.macroFat,
                        name: "Fat",
                        percent: Int(distribution.fatPercent)
                    )
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.offWhite)
                .shadow(color: .black.opacity(0.03), radius: 4, x: 0, y: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(macroCardAccessibilityLabel)
    }

    private var macroCardAccessibilityLabel: String {
        var label = title.isEmpty ? "Macro breakdown" : title
        if distribution.hasData {
            label += ": \(Int(distribution.proteinPercent))% protein, \(Int(distribution.carbsPercent))% carbs, \(Int(distribution.fatPercent))% fat"
        } else {
            label += ": No data available"
        }
        return label
    }
}

struct FullMacroLegendItem: View {
    let color: Color
    let name: String
    let percent: Int

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: 12, height: 12)

            Text(name)
                .font(.subheadline)
                .foregroundStyle(Color.charcoal)

            Spacer()

            Text("\(percent)%")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(Color.charcoal)
        }
    }
}

#Preview {
    VStack(spacing: 24) {
        // Ring with data
        MacroDistributionRing(
            distribution: MacroDistribution(
                proteinPercent: 28,
                carbsPercent: 45,
                fatPercent: 27
            )
        )

        // Ring without data
        MacroDistributionRing(
            distribution: MacroDistribution(
                proteinPercent: 0,
                carbsPercent: 0,
                fatPercent: 0
            )
        )

        // Full card
        MacroRingCard(
            distribution: MacroDistribution(
                proteinPercent: 30,
                carbsPercent: 40,
                fatPercent: 30
            ),
            title: "Weekly breakdown"
        )
    }
    .padding()
    .background(Color.gray.opacity(0.1))
}
