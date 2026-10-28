import AppKit
import SwiftUI

/// Side pane with the commit graph of one branch, merged with its upstream's history.
struct GraphPane: View {
    let target: GraphTarget
    @Binding var width: Double
    let maxWidth: CGFloat
    @Environment(ScanModel.self) private var model
    @State private var rows: [GraphRow] = []
    @State private var laneCount = 1
    @State private var error: String?
    @State private var isLoading = false
    @State private var refreshes = 0
    @State private var selectedCommit: String?
    @State private var dragStart: Double?

    static let minWidth: CGFloat = 300

    /// Reloads on a new target, a manual refresh, or when a fetch/pull/push moves the branch.
    private struct LoadKey: Hashable {
        let target: GraphTarget
        let status: BranchStatus?
        let refreshes: Int
    }

    private var status: BranchStatus? { model.statuses[target.repo]?[target.branch] }

    var body: some View {
        HStack(spacing: 0) {
            resizeHandle
            VStack(spacing: 0) {
                header
                Divider()
                content
            }
        }
        .frame(width: clamped(width))
        .background(Color(nsColor: .textBackgroundColor))
        .task(id: LoadKey(target: target, status: status, refreshes: refreshes)) { await load() }
    }

    private var resizeHandle: some View {
        Divider()
            .overlay {
                // Wider invisible grab area around the hairline.
                Color.clear
                    .frame(width: 8)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture(coordinateSpace: .global)
                            .onChanged { value in
                                let start = dragStart ?? width
                                dragStart = start
                                width = start - value.translation.width
                            }
                            .onEnded { _ in
                                width = clamped(width)
                                dragStart = nil
                            }
                    )
            }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text(target.branch)
                .font(.system(size: 11, weight: .semibold).monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
            if let status {
                Text("+ \(status.upstreamName)")
                    .font(.system(size: 11).monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(-1)
            }
            Spacer(minLength: 4)
            if isLoading { ProgressView().controlSize(.mini) }
            Button { refreshes += 1 } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .disabled(isLoading)
            .help("Reload graph")
            Button(action: model.closeGraph) {
                Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .help("Close graph")
        }
        .padding(.horizontal, 12)
        .frame(height: 26)
        .background(.bar)
    }

    @ViewBuilder private var content: some View {
        if let error {
            Text(error)
                .font(.system(size: 11))
                .foregroundStyle(.red)
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if rows.isEmpty {
            Text(isLoading ? "" : "No commits.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        CommitRow(row: row, laneCount: laneCount, isSelected: selectedCommit == row.commit.hash)
                            .onTapGesture { selectedCommit = selectedCommit == row.commit.hash ? nil : row.commit.hash }
                    }
                    if rows.count >= GitGraph.commitLimit {
                        Text("Showing the latest \(GitGraph.commitLimit) commits.")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .padding(10)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let commits = try await GitGraph.load(repo: target.repo, branch: target.branch,
                                                  upstreamRef: status?.isGone == false ? status?.upstreamRef : nil)
            let laidOut = await Task.detached(priority: .userInitiated) { GitGraph.layout(commits) }.value
            guard !Task.isCancelled else { return }
            rows = laidOut
            laneCount = laidOut.reduce(1) { max($0, $1.lanesIn.count, $1.lanesOut.count, $1.column + 1) }
            error = nil
        } catch {
            guard !Task.isCancelled else { return }
            rows = []
            self.error = error.localizedDescription
        }
    }

    private func clamped(_ value: Double) -> CGFloat {
        min(max(CGFloat(value), Self.minWidth), max(maxWidth, Self.minWidth))
    }
}

private struct CommitRow: View {
    let row: GraphRow
    let laneCount: Int
    let isSelected: Bool

    var body: some View {
        let commit = row.commit
        HStack(spacing: 6) {
            GraphCell(row: row)
                .frame(width: GraphCell.width(lanes: laneCount), height: GraphCell.rowHeight)
            ForEach(commit.refs, id: \.self) { RefBadge(ref: $0) }
            Text(commit.subject)
                .font(.system(size: 12, weight: commit.isHead ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            Spacer(minLength: 8)
            Text(commit.author)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: 110, alignment: .trailing)
                .layoutPriority(-1)
            Text(commit.date, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .fixedSize()
            Text(commit.shortHash)
                .font(.system(size: 11).monospaced())
                .foregroundStyle(.tertiary)
                .fixedSize()
        }
        .padding(.leading, 6)
        .padding(.trailing, 12)
        .frame(height: GraphCell.rowHeight)
        .background(isSelected ? Color.accentColor.opacity(0.18) : .clear)
        .contentShape(Rectangle())
        .help("\(commit.hash)\n\(commit.author) · \(commit.date.formatted(date: .abbreviated, time: .shortened))")
        .contextMenu {
            Button("Copy Commit Hash") { copy(commit.hash) }
            Button("Copy Subject") { copy(commit.subject) }
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// The lanes for one row: lines from the row above into this commit's dot, lines out of it to
/// its parents, and straight lines for lanes passing by.
private struct GraphCell: View {
    let row: GraphRow

    static let rowHeight: CGFloat = 24
    static let laneWidth: CGFloat = 14
    /// Very wide histories are clipped rather than squeezing the commit text out.
    static let maxLanes = 12

    static func width(lanes: Int) -> CGFloat { CGFloat(min(lanes, maxLanes)) * laneWidth + 6 }

    nonisolated static let palette: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .yellow, .red, .indigo, .mint]
    nonisolated static func color(_ lane: Int) -> Color { palette[lane % palette.count] }

    var body: some View {
        Canvas { context, size in
            let mid = size.height / 2
            func x(_ lane: Int) -> CGFloat { 3 + Self.laneWidth / 2 + CGFloat(lane) * Self.laneWidth }
            let dot = CGPoint(x: x(row.column), y: mid)

            func stroke(from: CGPoint, to: CGPoint, lane: Int) {
                var path = Path()
                path.move(to: from)
                if from.x == to.x {
                    path.addLine(to: to)
                } else {
                    // Vertical tangents at both ends, so lanes bend smoothly into each other.
                    let bend = (to.y - from.y) / 2
                    path.addCurve(to: to, control1: CGPoint(x: from.x, y: from.y + bend),
                                  control2: CGPoint(x: to.x, y: to.y - bend))
                }
                context.stroke(path, with: .color(Self.color(lane)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            }

            for (lane, heading) in row.lanesIn.enumerated() {
                guard let heading else { continue }
                if heading == row.commit.hash {
                    stroke(from: CGPoint(x: x(lane), y: 0), to: dot, lane: lane)
                } else {
                    stroke(from: CGPoint(x: x(lane), y: 0), to: CGPoint(x: x(lane), y: size.height), lane: lane)
                }
            }
            for column in row.parentColumns {
                stroke(from: dot, to: CGPoint(x: x(column), y: size.height), lane: column)
            }

            let radius: CGFloat = row.commit.isHead ? 4.5 : 3.5
            let circle = Path(ellipseIn: CGRect(x: dot.x - radius, y: dot.y - radius, width: radius * 2, height: radius * 2))
            if row.commit.parents.count > 1 {
                // Merge commits are hollow.
                context.fill(circle, with: .color(Color(nsColor: .textBackgroundColor)))
                context.stroke(circle, with: .color(Self.color(row.column)), lineWidth: 1.6)
            } else {
                context.fill(circle, with: .color(Self.color(row.column)))
            }
        }
        .clipped()
    }
}

private struct RefBadge: View {
    let ref: GraphRef

    var body: some View {
        let color: Color = switch ref.kind {
        case .local: .green
        case .remote: .blue
        case .tag: .orange
        }
        HStack(spacing: 2) {
            if ref.kind == .tag {
                Image(systemName: "tag.fill").font(.system(size: 8))
            }
            Text(ref.name)
                .font(.system(size: 10, weight: .medium).monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
        .frame(maxWidth: 160)
        .fixedSize(horizontal: false, vertical: true)
        .help(ref.name)
    }
}
