import SwiftUI

/// The detail area when nothing is selected: where every scanned repo stands.
struct Overview: View {
    @Environment(ScanModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            VStack(alignment: .leading, spacing: 6) {
                Text("All repositories")
                    .font(Typeface.ui(20, .semibold))
                    .foregroundStyle(Palette.text)
                Text("Select a repository to see its branches, worktrees and history, or a folder to manage it.")
                    .font(.dsBody)
                    .foregroundStyle(Palette.textMuted)
                    .lineSpacing(3)
            }

            if model.isScanning && model.repos.isEmpty {
                HStack(spacing: 8) {
                    Spinner()
                    Text("Scanning…")
                        .font(.dsBody)
                        .foregroundStyle(Palette.textMuted)
                }
            } else {
                // One board split by rules rather than four separate cards: the figures are read together.
                HStack(spacing: 0) {
                    Stat(value: model.repos.count, label: model.repos.count == 1 ? "Repository" : "Repositories",
                         detail: "in \(model.roots.count) folder\(model.roots.count == 1 ? "" : "s")")
                    Hairline(vertical: true)
                    Stat(value: totals.behind, label: "To pull", detail: "commits behind upstream",
                         color: totals.behind > 0 ? Palette.accent : nil)
                    Hairline(vertical: true)
                    Stat(value: totals.ahead, label: "To push", detail: "commits ahead of upstream",
                         color: totals.ahead > 0 ? Palette.positive : nil)
                    Hairline(vertical: true)
                    Stat(value: localOnly, label: "Local only", detail: "repositories with no remote")
                }
                // Every cell as tall as the tallest.
                .fixedSize(horizontal: false, vertical: true)
                .overlay(RoundedRectangle(cornerRadius: Metric.radiusLarge, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 1))
            }

            VStack(alignment: .leading, spacing: 10) {
                Shortcut(keys: ["⌘", "F"], action: "Filter repositories")
                Shortcut(keys: ["⇧", "⌘", "O"], action: "Add folders")
                Shortcut(keys: ["⌘", "R"], action: "Rescan")
                Shortcut(keys: ["⇧", "⌘", "Y"], action: "Show output")
            }
        }
        .frame(maxWidth: 640, alignment: .leading)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var totals: (behind: Int, ahead: Int) {
        model.statuses.values.flatMap(\.values).reduce((0, 0)) { ($0.0 + $1.behind, $0.1 + $1.ahead) }
    }

    private var localOnly: Int { model.repos.filter(\.isLocalOnly).count }
}

private struct Stat: View {
    let value: Int
    let label: String
    let detail: String
    var color: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.dsLabel)
                .foregroundStyle(Palette.textMuted)
            Text("\(value)")
                .font(Typeface.mono(26, .medium))
                .foregroundStyle(color ?? Palette.text)
                .contentTransition(.numericText())
            Text(detail)
                .font(.dsCaption)
                .foregroundStyle(Palette.textFaint)
                // Two lines in every cell, so the numbers line up whatever wraps.
                .lineLimit(2, reservesSpace: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }
}

/// A shortcut as keycaps, one per key, then what it does.
private struct Shortcut: View {
    let keys: [String]
    let action: String

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 3) {
                ForEach(keys, id: \.self) { Keycap($0) }
            }
            .frame(width: 76, alignment: .leading)
            Text(action)
                .font(.dsSmall)
                .foregroundStyle(Palette.textMuted)
        }
        .accessibilityElement(children: .combine)
    }
}
