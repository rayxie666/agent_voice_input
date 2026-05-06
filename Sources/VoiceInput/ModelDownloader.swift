import Foundation

/// Downloads `ggml-medium.bin` from Hugging Face into Application Support, with
/// live progress reporting so the menu-bar UI can render a progress bar. We use
/// the delegate-based `URLSession` API (rather than `async/await download(from:)`)
/// because only the delegate path exposes incremental byte counts.
@MainActor
final class ModelDownloader: NSObject, ObservableObject {
    enum State: Equatable {
        case idle
        case downloading
        case completed
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var bytesDownloaded: Int64 = 0
    @Published private(set) var totalBytes: Int64 = 0
    @Published private(set) var progress: Double = 0

    /// 1.5GB Hugging Face mirror — same source whisper.cpp's own
    /// `download-ggml-model.sh` uses.
    static let modelURL = URL(string:
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin")!

    static let destination: URL = {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VoiceInput", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
        return support.appendingPathComponent("ggml-medium.bin")
    }()

    /// Fired exactly once after a successful download completes (file moved
    /// into place). Coordinator subscribes to trigger a model reload.
    var onCompleted: (() -> Void)?

    private var task: URLSessionDownloadTask?
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 60 * 60  // 1h ceiling for full DL
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    func start() {
        guard state != .downloading else { return }
        state = .downloading
        bytesDownloaded = 0
        totalBytes = 0
        progress = 0

        do {
            try FileManager.default.createDirectory(
                at: Self.destination.deletingLastPathComponent(),
                withIntermediateDirectories: true)
        } catch {
            state = .failed("无法创建模型目录：\(error.localizedDescription)")
            return
        }

        let task = session.downloadTask(with: Self.modelURL)
        self.task = task
        task.resume()
    }

    func cancel() {
        task?.cancel()
        task = nil
        state = .idle
    }

    /// Human-friendly "X.Y GB / Z.W GB" for the progress label.
    static func formatBytes(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useGB, .useMB]
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }
}

extension ModelDownloader: URLSessionDownloadDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let written = totalBytesWritten
        let expected = totalBytesExpectedToWrite
        Task { @MainActor in
            self.bytesDownloaded = written
            self.totalBytes = expected
            self.progress = expected > 0 ? Double(written) / Double(expected) : 0
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // The temp file at `location` is deleted as soon as this delegate
        // returns, so we move it synchronously here (off the main actor —
        // the delegate queue is a background queue).
        let dest = ModelDownloader.destination
        let result: Result<Void, Error> = Result {
            let fm = FileManager.default
            try fm.createDirectory(at: dest.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
            if fm.fileExists(atPath: dest.path) {
                try fm.removeItem(at: dest)
            }
            try fm.moveItem(at: location, to: dest)
        }

        Task { @MainActor in
            switch result {
            case .success:
                self.state = .completed
                self.progress = 1.0
                self.onCompleted?()
            case .failure(let err):
                self.state = .failed("写入模型文件失败：\(err.localizedDescription)")
            }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        // didFinishDownloadingTo is the success path; this fires for errors
        // (or for cancellation). Successful completions also call this with
        // error == nil — ignore those so we don't override the .completed
        // state set above.
        guard let error = error else { return }
        // Ignore cancellation — we already set .idle in cancel().
        let nsError = error as NSError
        if nsError.code == NSURLErrorCancelled { return }
        Task { @MainActor in
            self.state = .failed("下载失败：\(error.localizedDescription)")
        }
    }
}
