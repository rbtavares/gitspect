import Foundation

struct GitError: LocalizedError, Sendable {
    let message: String
    /// The message is git's own stderr (as opposed to a timeout or bare exit status).
    var fromStderr = false
    var errorDescription: String? { message }
}

enum Git {
    /// How long to wait for the output pipes to close after git exits. Background helpers
    /// (ssh ControlMaster, credential daemons) can inherit them and keep them open indefinitely.
    private static let drainGrace: Duration = .seconds(1)

    /// Runs `git -C <dir> <args>` and returns stdout. Never prompts: stdin is closed and terminal prompts are off.
    /// `onOutput` receives stdout and stderr chunks as they arrive; `timeout` terminates git if it hangs.
    static func run(
        _ args: [String], in dir: URL, timeout: Duration? = nil,
        onOutput: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", dir.path] + args
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"
        // Apps launched from Finder get a minimal PATH; hooks and credential helpers often live in Homebrew.
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin")
        process.environment = env

        let out = Pipe(), err = Pipe()
        let collector = OutputCollector()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        for (pipe, isError) in [(out, false), (err, true)] {
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    collector.close(isError: isError)
                } else {
                    collector.append(data, isError: isError)
                    onOutput?(String(decoding: data, as: UTF8.self))
                }
            }
        }

        let watchdog = timeout.map { limit in
            Task.detached {
                try? await Task.sleep(for: limit)
                if !Task.isCancelled && process.isRunning { collector.timedOut = true; process.terminate() }
            }
        }
        defer { watchdog?.cancel() }

        // `waitUntilExit()` needs a running run loop, which Swift concurrency threads don't have:
        // it can block forever after git has exited. The termination handler doesn't.
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        } as Int32
        let deadline = ContinuousClock.now + drainGrace
        while !collector.isClosed && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        out.fileHandleForReading.readabilityHandler = nil
        err.fileHandleForReading.readabilityHandler = nil

        guard status == 0 else {
            let message = collector.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if collector.timedOut { throw GitError(message: "git timed out") }
            if message.isEmpty { throw GitError(message: "git exited with status \(status)") }
            throw GitError(message: message, fromStderr: true)
        }
        return collector.stdout
    }
}

/// Accumulates a process's output from pipe callbacks on arbitrary threads.
private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var out = Data(), err = Data()
    private var closedPipes = 0
    private var _timedOut = false

    func append(_ data: Data, isError: Bool) {
        lock.withLock { if isError { err.append(data) } else { out.append(data) } }
    }

    func close(isError: Bool) { lock.withLock { closedPipes += 1 } }

    var isClosed: Bool { lock.withLock { closedPipes == 2 } }
    var stdout: String { lock.withLock { String(decoding: out, as: UTF8.self) } }
    var stderr: String { lock.withLock { String(decoding: err, as: UTF8.self) } }
    var timedOut: Bool {
        get { lock.withLock { _timedOut } }
        set { lock.withLock { _timedOut = newValue } }
    }
}

struct BranchStatus: Sendable, Hashable {
    /// Full upstream ref, e.g. `refs/remotes/origin/main`.
    let upstreamRef: String
    let upstreamName: String
    let remote: String
    /// The branch's ref on the remote, e.g. `refs/heads/main`.
    let remoteRef: String
    let ahead: Int
    let behind: Int
    /// The upstream branch was deleted on the remote.
    let isGone: Bool

    var isDiverged: Bool { ahead > 0 && behind > 0 }

    /// Mirrors git's default `push.default=simple`: only push to a remote branch of the same name.
    func canPush(_ branch: String) -> Bool { remoteRef == "refs/heads/\(branch)" }

    /// Ahead/behind for every local branch with an upstream, keyed by branch name.
    static func load(repo: URL) async throws -> [String: BranchStatus] {
        let fields = ["refname", "upstream", "upstream:short", "upstream:remotename", "upstream:remoteref",
                      "upstream:track,nobracket"]
        let format = fields.map { "%(\($0))" }.joined(separator: "%00")
        let output = try await Git.run(
            ["--no-optional-locks", "for-each-ref", "--format=\(format)", "refs/heads"], in: repo
        )

        var result: [String: BranchStatus] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == fields.count, !parts[1].isEmpty else { continue }
            let track = parts[5]
            result[String(parts[0].dropFirst("refs/heads/".count))] = BranchStatus(
                upstreamRef: parts[1], upstreamName: parts[2], remote: parts[3], remoteRef: parts[4],
                ahead: count(in: track, label: "ahead"), behind: count(in: track, label: "behind"),
                isGone: track == "gone"
            )
        }
        return result
    }

    /// Parses `ahead 1, behind 2`.
    private static func count(in track: String, label: String) -> Int {
        for part in track.split(separator: ",") {
            let words = part.split(separator: " ")
            if words.count == 2, words[0] == label { return Int(words[1]) ?? 0 }
        }
        return 0
    }
}
