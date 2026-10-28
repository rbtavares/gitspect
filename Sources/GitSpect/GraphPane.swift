import AppKit
import SwiftUI

/// Side pane with the commit graph of one branch, merged with its upstream's history.
struct GraphPane: View {
    let target: GraphTarget
    /// Share of `totalWidth` the pane takes; kept as a fraction so it scales with the window.
    @Binding var fraction: Double
    /// Width shared by the repo view and this pane.
    let totalWidth: CGFloat
    @Environment(ScanModel.self) private var model
    @State private var rows: [GraphRow] = []
    @State private var laneCount = 1
    @State private var error: String?
    @State private var isLoading = false
    @State private var refreshes = 0
    @State private var selectedCommit: String?
    @State private var scrollTarget: String?
    @State private var dragStart: CGFloat?
    @AppStorage("commitDrawerHeight") private var drawerHeight = 260.0

    static let minWidth: CGFloat = 300
    /// Room always left for the repo view.
    static let minDetailWidth: CGFloat = 320

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
        .frame(width: clamped(totalWidth * fraction))
        .background(Color(nsColor: .textBackgroundColor))
        .task(id: LoadKey(target: target, status: status, refreshes: refreshes)) { await load() }
        .onChange(of: target) { selectedCommit = nil }
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
                                guard totalWidth > 0 else { return }
                                let start = dragStart ?? clamped(totalWidth * fraction)
                                dragStart = start
                                fraction = clamped(start - value.translation.width) / totalWidth
                            }
                            .onEnded { _ in dragStart = nil }
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
            GeometryReader { proxy in
                VStack(spacing: 0) {
                    commitList
                    if let hash = selectedCommit, let row = rows.first(where: { $0.commit.hash == hash }) {
                        CommitDrawer(
                            commit: row.commit, repo: target.repo, height: $drawerHeight,
                            maxHeight: proxy.size.height - 80,
                            isInGraph: { parent in rows.contains { $0.commit.hash == parent } },
                            select: { parent in
                                selectedCommit = parent
                                scrollTarget = parent
                            },
                            close: { selectedCommit = nil }
                        )
                    }
                }
            }
        }
    }

    private var commitList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        CommitRow(row: row, laneCount: laneCount, isSelected: selectedCommit == row.commit.hash)
                            .id(row.commit.hash)
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
            // Jumping to a parent from the drawer brings it into view.
            .onChange(of: scrollTarget) {
                guard let scrollTarget else { return }
                withAnimation(.snappy(duration: 0.25)) { proxy.scrollTo(scrollTarget, anchor: .center) }
                self.scrollTarget = nil
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

    private func clamped(_ value: CGFloat) -> CGFloat {
        min(max(value, Self.minWidth), max(totalWidth - Self.minDetailWidth, Self.minWidth))
    }
}

private struct CommitRow: View {
    let row: GraphRow
    let laneCount: Int
    let isSelected: Bool

    var body: some View {
        let commit = row.commit
        let height = GraphCell.height(for: commit)
        HStack(alignment: .top, spacing: 6) {
            GraphCell(row: row)
                .frame(width: GraphCell.width(lanes: laneCount), height: height)
            VStack(alignment: .leading, spacing: 0) {
                summary
                    .frame(height: GraphCell.rowHeight)
                // Branches and tags on a line of their own, under the subject.
                if !commit.refs.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(commit.refs, id: \.self) { RefBadge(ref: $0) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipped()
                }
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 12)
        .frame(height: height)
        .background(isSelected ? Color.accentColor.opacity(0.18) : .clear)
        .contentShape(Rectangle())
        .help("\(commit.hash)\n\(commit.author) · \(commit.date.formatted(date: .abbreviated, time: .shortened))")
        .contextMenu {
            Button("Copy Commit Hash") { copy(commit.hash) }
            Button("Copy Subject") { copy(commit.subject) }
        }
    }

    private var summary: some View {
        let commit = row.commit
        return HStack(spacing: 6) {
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
    }
}

/// The lanes for one row: lines from the row above into this commit's dot, lines out of it to
/// its parents, and straight lines for lanes passing by.
private struct GraphCell: View {
    let row: GraphRow

    /// Height of a row's first line, which the commit's dot is centred on.
    static let rowHeight: CGFloat = 24
    /// Extra height for the line of ref badges.
    static let refsHeight: CGFloat = 18

    static func height(for commit: GraphCommit) -> CGFloat {
        commit.refs.isEmpty ? rowHeight : rowHeight + refsHeight
    }
    static let laneWidth: CGFloat = 14
    /// Very wide histories are clipped rather than squeezing the commit text out.
    static let maxLanes = 12

    static func width(lanes: Int) -> CGFloat { CGFloat(min(lanes, maxLanes)) * laneWidth + 6 }

    nonisolated static let palette: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .yellow, .red, .indigo, .mint]
    nonisolated static func color(_ lane: Int) -> Color { palette[lane % palette.count] }

    var body: some View {
        Canvas { context, size in
            // Level with the subject; lines still run the full height of taller rows.
            let mid = Self.rowHeight / 2
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
                // Long names are cut to 160pt; fixedSize below keeps short ones at their own width
                // instead of stretching to soak up the row's spare space.
                .frame(maxWidth: 160)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
        .fixedSize()
        .help(ref.name)
    }
}

/// Bottom drawer in the graph pane with one commit's message, people, parents and changed files.
private struct CommitDrawer: View {
    let commit: GraphCommit
    let repo: URL
    @Binding var height: Double
    let maxHeight: CGFloat
    /// Whether a parent is loaded in the graph, so it can be jumped to.
    let isInGraph: (String) -> Bool
    let select: (String) -> Void
    let close: () -> Void
    @State private var details: CommitDetails?
    @State private var error: String?
    @State private var dragStart: Double?

    private static let minHeight: CGFloat = 120

    var body: some View {
        VStack(spacing: 0) {
            resizeHandle
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    message
                    people
                    if !commit.parents.isEmpty || !commit.refs.isEmpty { links }
                    files
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(height: clamped(height))
        .background(Color(nsColor: .textBackgroundColor))
        .task(id: commit.hash) { await load() }
    }

    private var resizeHandle: some View {
        Divider()
            .overlay {
                Color.clear
                    .frame(height: 8)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture(coordinateSpace: .global)
                            .onChanged { value in
                                let start = dragStart ?? height
                                dragStart = start
                                height = start - value.translation.height
                            }
                            .onEnded { _ in
                                height = clamped(height)
                                dragStart = nil
                            }
                    )
            }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("Commit")
                .font(.system(size: 11, weight: .semibold))
            Text(commit.shortHash)
                .font(.system(size: 11).monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Button { copy(commit.hash) } label: {
                Image(systemName: "doc.on.doc").font(.system(size: 9))
            }
            .buttonStyle(.borderless)
            .help("Copy full hash")
            Spacer()
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .help("Close commit details")
        }
        .padding(.horizontal, 12)
        .frame(height: 26)
        .background(.bar)
    }

    @ViewBuilder private var message: some View {
        let text = details?.message ?? commit.subject
        let lines = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        VStack(alignment: .leading, spacing: 6) {
            Text(lines.first.map(String.init) ?? "")
                .font(.system(size: 13, weight: .semibold))
            if lines.count > 1 {
                let body = lines[1].trimmingCharacters(in: .whitespacesAndNewlines)
                if !body.isEmpty {
                    Text(body)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var people: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
            if let details {
                person("Author", details.authorName, details.authorEmail, details.authorDate)
                // Rebases and cherry-picks keep the author but change who committed, and when.
                if details.committerEmail != details.authorEmail
                    || abs(details.commitDate.timeIntervalSince(details.authorDate)) > 60 {
                    person("Committer", details.committerName, details.committerEmail, details.commitDate)
                }
            } else {
                GridRow {
                    label("Author")
                    Text("\(commit.author) · \(commit.date.formatted(date: .abbreviated, time: .shortened))")
                }
            }
        }
        .font(.system(size: 11))
    }

    private func person(_ role: String, _ name: String, _ email: String, _ date: Date) -> some View {
        GridRow {
            label(role)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(name) <\(email)>").textSelection(.enabled)
                Text("\(date.formatted(date: .abbreviated, time: .shortened)) · \(date.formatted(.relative(presentation: .named)))")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var links: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
            if !commit.parents.isEmpty {
                GridRow {
                    label(commit.parents.count > 1 ? "Parents" : "Parent")
                    HStack(spacing: 8) {
                        ForEach(commit.parents, id: \.self) { parent in
                            Button(String(parent.prefix(7))) { select(parent) }
                                .buttonStyle(.link)
                                .font(.system(size: 11).monospaced())
                                .disabled(!isInGraph(parent))
                                .help(isInGraph(parent) ? "Show \(parent)" : "\(parent) is older than the commits loaded")
                        }
                    }
                }
            }
            if !commit.refs.isEmpty {
                GridRow {
                    label("Refs")
                    HStack(spacing: 4) {
                        ForEach(commit.refs, id: \.self) { RefBadge(ref: $0) }
                    }
                }
            }
        }
        .font(.system(size: 11))
    }

    @ViewBuilder private var files: some View {
        if let error {
            Text(error)
                .font(.system(size: 11))
                .foregroundStyle(.red)
                .textSelection(.enabled)
        } else if let details {
            let added = details.files.reduce(0) { $0 + ($1.added ?? 0) }
            let deleted = details.files.reduce(0) { $0 + ($1.deleted ?? 0) }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("\(details.files.count) file\(details.files.count == 1 ? "" : "s") changed")
                        .font(.system(size: 11, weight: .semibold))
                    LineCounts(added: added, deleted: deleted)
                    if commit.parents.count > 1 {
                        Text("against first parent")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(details.files) { FileRow(file: $0) }
                }
            }
        } else {
            ProgressView().controlSize(.small)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.trailing)
    }

    private func load() async {
        details = nil
        error = nil
        do {
            let loaded = try await GitGraph.details(repo: repo, commit: commit)
            guard !Task.isCancelled else { return }
            details = loaded
        } catch {
            guard !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
    }

    private func clamped(_ value: Double) -> CGFloat {
        min(max(CGFloat(value), Self.minHeight), max(maxHeight, Self.minHeight))
    }
}

private struct FileRow: View {
    let file: FileChange

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: file.oldPath == nil ? "doc" : "arrow.right.doc.on.clipboard")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .frame(width: 14)
            Text(file.oldPath.map { "\($0) → \(file.path)" } ?? file.path)
                .font(.system(size: 11).monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
                .help(file.oldPath.map { "Renamed from \($0)" } ?? file.path)
            Spacer(minLength: 8)
            if let added = file.added, let deleted = file.deleted {
                LineCounts(added: added, deleted: deleted)
            } else {
                Text("binary")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(height: 18)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Copy Path") { copy(file.path) }
        }
    }
}

private struct LineCounts: View {
    let added: Int
    let deleted: Int

    var body: some View {
        HStack(spacing: 4) {
            Text("+\(added)").foregroundStyle(.green)
            Text("−\(deleted)").foregroundStyle(.red)
        }
        .font(.system(size: 11, weight: .medium).monospacedDigit())
        .fixedSize()
    }
}

private func copy(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}
