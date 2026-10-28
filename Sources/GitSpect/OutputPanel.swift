import AppKit
import SwiftUI

/// Bottom drawer with every command GitSpect ran and its live output.
struct OutputPanel: View {
    @Binding var height: Double
    let maxHeight: CGFloat
    let close: () -> Void
    @Environment(ScanModel.self) private var model
    @State private var dragStart: Double?

    private static let minHeight: CGFloat = 90

    var body: some View {
        VStack(spacing: 0) {
            Divider()
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
            HStack(spacing: 8) {
                Text("Output")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Button("Clear", action: model.clearLog)
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
                    .disabled(model.log.isEmpty)
                Button(action: close) { Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)) }
                    .buttonStyle(.borderless)
                    .help("Hide output (⇧⌘Y)")
            }
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(.bar)
            Divider()

            if model.log.isEmpty {
                Text("Commands like fetch, pull and push show their output here.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(model.log) { LogEntryView(entry: $0).id($0.id) }
                        }
                        .padding(10)
                        Color.clear.frame(height: 1).id("end")
                    }
                    // Follow new commands and output as they stream in.
                    .onChange(of: model.log.last?.output.count) { proxy.scrollTo("end", anchor: .bottom) }
                    .onChange(of: model.log.count) { proxy.scrollTo("end", anchor: .bottom) }
                    .onAppear { proxy.scrollTo("end", anchor: .bottom) }
                }
            }
        }
        .frame(height: clamped(height))
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func clamped(_ value: Double) -> CGFloat {
        min(max(CGFloat(value), Self.minHeight), max(maxHeight, Self.minHeight))
    }
}

private struct LogEntryView: View {
    let entry: LogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                statusIcon.frame(width: 12)
                Text(entry.repo)
                    .font(.system(size: 11, weight: .semibold))
                Text(entry.command)
                    .font(.system(size: 11).monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer(minLength: 8)
                Text(timing)
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            if !entry.output.isEmpty {
                Text(cleaned(entry.output))
                    .font(.system(size: 11).monospaced())
                    .foregroundStyle(entry.status == .failed ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .textSelection(.enabled)
                    .padding(.leading, 18)
            }
        }
    }

    @ViewBuilder private var statusIcon: some View {
        switch entry.status {
        case .running: ProgressView().controlSize(.mini)
        case .succeeded: Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.green)
        case .failed: Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.red)
        }
    }

    private var timing: String {
        let start = entry.startedAt.formatted(date: .omitted, time: .standard)
        guard let end = entry.finishedAt else { return start }
        return start + " · " + String(format: "%.1fs", end.timeIntervalSince(entry.startedAt))
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
