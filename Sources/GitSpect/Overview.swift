import SwiftUI

/// The detail area when nothing is selected: a summary of every scanned repo.
struct Overview: View {
    @Environment(ScanModel.self) private var model

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 10) {
                if let image = NSApp.applicationIconImage {
                    Image(nsImage: image)
                        .resizable()
                        .frame(width: 80, height: 80)
                        .accessibilityHidden(true)
                }
                Text("GitSpect")
                    .font(.system(size: 22, weight: .semibold))
                Text("Select a repository to see its branches, worktrees and history, or a folder to manage it.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }

            if model.isScanning && model.repos.isEmpty {
                ProgressView("Scanning…")
                    .controlSize(.small)
            } else {
                HStack(spacing: 12) {
                    Stat(value: model.repos.count, label: model.repos.count == 1 ? "Repository" : "Repositories",
                         detail: "in \(model.roots.count) folder\(model.roots.count == 1 ? "" : "s")")
                    Stat(value: totals.behind, label: "To Pull", detail: "commits behind upstream",
                         color: totals.behind > 0 ? .blue : nil)
                    Stat(value: totals.ahead, label: "To Push", detail: "commits ahead of upstream",
                         color: totals.ahead > 0 ? .green : nil)
                    Stat(value: localOnly, label: "Local Only", detail: "repositories with no remote")
                }
                // Every card as tall as the tallest.
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 640)
            }

            HStack(spacing: 18) {
                Shortcut(keys: ["⇧", "⌘", "O"], action: "Add Folders")
                Shortcut(keys: ["⌘", "R"], action: "Rescan")
                Shortcut(keys: ["⇧", "⌘", "Y"], action: "Show Output")
            }
        }
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
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.system(size: 26, weight: .semibold).monospacedDigit())
                .foregroundStyle(color.map(AnyShapeStyle.init) ?? AnyShapeStyle(.primary))
                .contentTransition(.numericText())
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                // Two lines in every card, so the numbers line up whatever wraps.
                .lineLimit(2, reservesSpace: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// A shortcut as keycaps, one per key, then what it does.
private struct Shortcut: View {
    let keys: [String]
    let action: String

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 3) {
                ForEach(keys, id: \.self) { key in
                    Text(key)
                        .font(.system(size: 12, weight: .medium))
                        .frame(minWidth: 20, minHeight: 20)
                        .padding(.horizontal, 2)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
            }
            Text(action)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
