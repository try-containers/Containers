//
//  FileDownloader.swift
//  Containers
//
//  A download that says how far along it is, for what arrives over HTTP
//  rather than as an image.
//

import ContainerizationExtras
import Foundation

/// Downloads a file to `destination`, reporting the bytes as they land.
///
/// The delegate takes delivery of the file itself. `URLSession`'s async
/// `download(from:)` and its completion-handler form both leave the progress
/// callbacks unsent, so a task with neither is the only one that reports.
final class FileDownloader: NSObject, URLSessionDownloadDelegate,
    @unchecked Sendable
{
    private let destination: URL
    private let progress: ProgressReporter
    private var continuation: CheckedContinuation<URLResponse, Error>?
    private var reportedBytes: Int64 = 0
    private var reportedTotal = false

    init(destination: URL, progress: ProgressReporter) {
        self.destination = destination
        self.progress = progress
    }

    func download(from url: URL) async throws -> URLResponse {
        let session = URLSession(
            configuration: .default,
            delegate: self,
            delegateQueue: nil
        )

        defer {
            session.finishTasksAndInvalidate()
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        var events: [ProgressEvent] = []

        if !reportedTotal, totalBytesExpectedToWrite > 0 {
            reportedTotal = true
            events.append(.addTotalSize(totalBytesExpectedToWrite))
        }

        // The callback counts from the start of the download; the reporter
        // adds up what it is given, so it is told what has arrived since.
        events.append(.addSize(totalBytesWritten - reportedBytes))
        reportedBytes = totalBytesWritten

        let progress = self.progress
        Task { @MainActor in
            progress.update(events)
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            continuation?.resume(returning: downloadTask.response ?? URLResponse())
        } catch {
            continuation?.resume(throwing: error)
        }

        continuation = nil
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return }

        continuation?.resume(throwing: error)
        continuation = nil
    }
}
