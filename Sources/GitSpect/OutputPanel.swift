import AppKit
import SwiftUI

/// Bottom drawer with every command GitSpect ran and its live output.
struct OutputPanel: View {
    @Binding var height: Double
    let maxHeight: CGFloat
    let close: () -> Void
    @Environment(ScanModel.self) private var model
    @State private var dragStart: Double?

    private static let minHeight: CGFloat = 96

    var body: some View {
        VStack(spacing: 0) {
            Hairline()
                .overlay {
                    // Wider invisible grab area around the hairline.
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
                .zIndex(1)
            PaneHeader {
                Text("Output")
                    .font(.dsLabel)
                    .foregroundStyle(Palette.textMuted)
                Spacer()
                Button("Clear", action: model.clearLog)
                    .buttonStyle(.ds(.ghost, small: true))
                    .disabled(model.log.isEmpty)
                IconButton(symbol: "xmark", help: "Hide output (⇧⌘Y)", size: 10, action: close)
            }

            if model.log.isEmpty {
                Text("Commands like fetch, pull and push show their output here.")
                    .font(.dsSmall)
                    .foregroundStyle(Palette.textFaint)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        // Not lazy: the log is capped at a couple of hundred entries, and a lazy
                        // stack rebuilds rows as streaming output moves them, which flickers.
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(entries) { LogEntryView(entry: $0) }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Color.clear.frame(height: 1).id("end")
                    }
                    // Stays pinned to the newest line as output grows, without a jump per chunk.
                    .defaultScrollAnchor(.bottom)
                    // A new command, or one finishing and moving up, brings the end back into view.
                    .onChange(of: model.log.count) { proxy.scrollTo("end", anchor: .bottom) }
                    .onChange(of: model.log.filter { $0.status == .running }.count) {
                        proxy.scrollTo("end", anchor: .bottom)
                    }
                }
            }
        }
        .frame(height: clamped(height))
        .background(Palette.canvas)
    }

    /// Finished commands in the order they finished, then the ones still running at the bottom.
    private var entries: [LogEntry] {
        let finished = model.log
            .filter { $0.status != .running }
            .sorted { ($0.finishedAt ?? $0.startedAt) < ($1.finishedAt ?? $1.startedAt) }
        return finished + model.log.filter { $0.status == .running }
    }

    private func clamped(_ value: Double) -> CGFloat {
        min(max(CGFloat(value), Self.minHeight), max(maxHeight, Self.minHeight))
    }
}

private struct LogEntryView: View {
    let entry: LogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                statusIcon.frame(width: 12)
                Text(entry.repo)
                    .font(.dsLabel)
                    .foregroundStyle(Palette.text)
                Text(entry.command)
                    .font(.dsMonoSmall)
                    .foregroundStyle(Palette.textMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer(minLength: 8)
                Text(timing)
                    .font(.dsMonoSmall)
                    .foregroundStyle(Palette.textFaint)
            }
            if !entry.output.isEmpty {
                Text(cleaned(entry.output))
                    .font(.dsMonoSmall)
                    .lineSpacing(3)
                    .foregroundStyle(entry.status == .failed ? Palette.danger : Palette.textMuted)
                    .textSelection(.enabled)
                    .padding(.leading, 20)
            }
        }
    }

    @ViewBuilder private var statusIcon: some View {
        switch entry.status {
        case .running:
            Spinner(size: 10)
        case .succeeded:
            Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.positive)
                .accessibilityLabel("Succeeded")
        case .failed:
            Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.danger)
                .accessibilityLabel("Failed")
        }
    }

    private var timing: String {
        let start = entry.startedAt.formatted(date: .omitted, time: .standard)
        guard let end = entry.finishedAt else { return start }
        return start + "  " + String(format: "%.1fs", end.timeIntervalSince(entry.startedAt))
    }

    /// Git redraws progress lines with `\r`; keep only the final state of each line.
    private func cleaned(_ output: String) -> String {
        output
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.split(separator: "\r").last.map(String.init) ?? "" }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
