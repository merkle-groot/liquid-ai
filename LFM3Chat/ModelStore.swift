import Foundation
import Observation

/// Downloads the LFM3-1.7B GGUF from Hugging Face on first launch and keeps it in Application Support.
@MainActor
@Observable
final class ModelStore {
    enum State: Equatable {
        case missing
        case downloading(progress: Double, received: Int64, total: Int64)
        case ready(URL)
        case failed(String)
    }

    nonisolated static let fileName = "LFM3-1.7B-QAD-Q4_0.gguf"
    static let remoteURL = URL(string: "https://huggingface.co/LiquidAI/LFM3-1.7B-GGUF/resolve/main/\(fileName)")!
    static let approxBytes: Int64 = 1_050_000_000

    private(set) var state: State = .missing
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var resumeData: Data?

    nonisolated static var localURL: URL {
        let dir = URL.applicationSupportDirectory.appending(path: "Models", directoryHint: .isDirectory)
        return dir.appending(path: fileName)
    }

    init() {
        if FileManager.default.fileExists(atPath: Self.localURL.path) {
            state = .ready(Self.localURL)
        }
    }

    func startDownload() {
        guard task == nil else { return }
        let delegate = DownloadDelegate(store: self)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let task = resumeData.map { session.downloadTask(withResumeData: $0) } ?? session.downloadTask(with: Self.remoteURL)
        resumeData = nil
        self.session = session
        self.task = task
        state = .downloading(progress: 0, received: 0, total: Self.approxBytes)
        task.resume()
    }

    func cancelDownload() {
        task?.cancel { [weak self] data in
            Task { @MainActor in self?.resumeData = data }
        }
        finishSession()
        state = .missing
    }

    func deleteModel() {
        try? FileManager.default.removeItem(at: Self.localURL)
        state = .missing
    }

    fileprivate func update(received: Int64, total: Int64) {
        guard task != nil else { return }
        let total = total > 0 ? total : Self.approxBytes
        state = .downloading(progress: Double(received) / Double(total), received: received, total: total)
    }

    fileprivate func finished(error: Error?) {
        if let error {
            let nsError = error as NSError
            if nsError.code == NSURLErrorCancelled { return }
            resumeData = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
            state = .failed(error.localizedDescription)
        } else if FileManager.default.fileExists(atPath: Self.localURL.path) {
            state = .ready(Self.localURL)
        } else {
            state = .failed("Download finished but the file is missing.")
        }
        finishSession()
    }

    private func finishSession() {
        session?.finishTasksAndInvalidate()
        session = nil
        task = nil
    }

    /// Moves the downloaded temp file into place. Runs on the URLSession delegate queue.
    nonisolated static func install(from tempURL: URL) throws {
        let fm = FileManager.default
        var dest = localURL
        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.removeItem(at: dest)
        try fm.moveItem(at: tempURL, to: dest)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try dest.setResourceValues(values)
    }
}

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    weak var store: ModelStore?
    private var installError: Error?

    init(store: ModelStore) { self.store = store }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        Task { @MainActor [weak store] in
            store?.update(received: totalBytesWritten, total: totalBytesExpectedToWrite)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            installError = URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "Server returned HTTP \(http.statusCode)"])
            return
        }
        do { try ModelStore.install(from: location) } catch { installError = error }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let err = error ?? installError
        Task { @MainActor [weak store] in
            store?.finished(error: err)
        }
    }
}
