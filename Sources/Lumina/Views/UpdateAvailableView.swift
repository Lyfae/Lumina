import SwiftUI
import AppKit

/// Update sheet with download progress — matches Lumina theme and fixed window sizing.
struct UpdateAvailableView: View {
    let currentVersion: String
    let newVersion: String
    let downloadURL: URL
    let onInstall: (URL) -> Void
    let onLater: () -> Void

    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var uiScale = UIScaleManager.shared
    @State private var isDownloading = false
    @State private var downloadProgress: Double = 0.0
    @State private var knowsContentLength = true
    @State private var downloadedFileURL: URL?
    @State private var downloadError: String?
    @State private var downloadTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: LuminaSpace.xl) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: uiScale.iconSize(.hero)))
                .foregroundStyle(themeManager.current.color)

            VStack(spacing: LuminaSpace.tight) {
                Text("Update Available")
                    .font(uiScale.font(.title).weight(.bold))
                Text("Lumina \(newVersion) is now available.")
                    .font(uiScale.font(.body).weight(.medium))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: LuminaSpace.xs) {
                Text("Version \(currentVersion) is currently installed.")
                    .font(uiScale.font(.callout))
                    .foregroundStyle(.secondary)
                Text("This update includes the latest features and fixes.")
                    .font(uiScale.font(.callout))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isDownloading || downloadedFileURL != nil {
                let progress = downloadedFileURL == nil ? downloadProgress : 1.0
                VStack(alignment: .leading, spacing: LuminaSpace.tight) {
                    if knowsContentLength || downloadedFileURL != nil {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                    } else {
                        ProgressView()
                            .progressViewStyle(.linear)
                    }
                    Text(downloadedFileURL == nil ? "Downloading…" : "Download complete — ready to install")
                        .font(uiScale.font(.caption))
                        .foregroundStyle(.secondary)
                }
            }

            if let downloadError {
                Text(downloadError)
                    .font(uiScale.font(.caption))
                    .foregroundStyle(LuminaStatusColor.error)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: LuminaSpace.md) {
                Button("Later", action: onLater)
                    .buttonStyle(LuminaSecondaryButtonStyle())
                    .controlSize(uiScale.controlSize())
                    .disabled(isDownloading && downloadedFileURL == nil)

                Button {
                    if let downloaded = downloadedFileURL {
                        onInstall(downloaded)
                    } else {
                        startDownload()
                    }
                } label: {
                    if isDownloading && downloadedFileURL == nil {
                        ProgressView()
                            .controlSize(.small)
                    } else if downloadError != nil && downloadedFileURL == nil {
                        Text("Retry")
                    } else {
                        Text(downloadedFileURL == nil ? "Download and Install" : "Install Update")
                    }
                }
                .buttonStyle(LuminaProminentButtonStyle())
                .controlSize(uiScale.controlSize())
                .disabled(isDownloading && downloadedFileURL == nil)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(LuminaSpace.xxl + LuminaSpace.xs)
        .scaledFrame(width: 420, height: 380)
        .background(Color.luminaBase)
        .tint(themeManager.current.color)
        .onDisappear {
            downloadTask?.cancel()
            downloadTask = nil
        }
    }

    private func startDownload() {
        downloadTask?.cancel()
        isDownloading = true
        downloadProgress = 0
        knowsContentLength = true
        downloadError = nil
        downloadedFileURL = nil

        downloadTask = Task {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("Lumina-Update-\(UUID().uuidString).dmg")
            var wroteFile = false

            do {
                let (bytes, response) = try await URLSession.shared.bytes(from: downloadURL)
                try Task.checkCancellation()

                let expected = response.expectedContentLength
                let hasLength = expected > 0
                await MainActor.run { knowsContentLength = hasLength }

                FileManager.default.createFile(atPath: tempURL.path, contents: nil)
                let handle = try FileHandle(forWritingTo: tempURL)
                wroteFile = true
                defer { try? handle.close() }

                var received: Int64 = 0
                var buffer = Data()
                buffer.reserveCapacity(65_536)
                var lastProgressUpdate = Date.distantPast
                let throttle: TimeInterval = 0.05

                for try await byte in bytes {
                    try Task.checkCancellation()
                    buffer.append(byte)
                    received += 1

                    if buffer.count >= 65_536 {
                        try handle.write(contentsOf: buffer)
                        buffer.removeAll(keepingCapacity: true)
                    }

                    guard hasLength else { continue }
                    let now = Date()
                    if now.timeIntervalSince(lastProgressUpdate) >= throttle {
                        lastProgressUpdate = now
                        let value = min(1.0, Double(received) / Double(expected))
                        await MainActor.run { downloadProgress = value }
                    }
                }

                if !buffer.isEmpty {
                    try handle.write(contentsOf: buffer)
                }

                if hasLength {
                    await MainActor.run { downloadProgress = 1.0 }
                }

                await MainActor.run {
                    downloadedFileURL = tempURL
                    isDownloading = false
                }
            } catch is CancellationError {
                if wroteFile {
                    try? FileManager.default.removeItem(at: tempURL)
                }
                await MainActor.run {
                    isDownloading = false
                    downloadProgress = 0
                }
            } catch {
                if wroteFile {
                    try? FileManager.default.removeItem(at: tempURL)
                }
                await MainActor.run {
                    isDownloading = false
                    downloadProgress = 0
                    downloadError = "Download failed. \(error.localizedDescription)"
                }
            }
        }
    }
}
