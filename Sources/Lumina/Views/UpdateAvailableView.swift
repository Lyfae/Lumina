import SwiftUI

/// Nice update sheet inspired by modern AI tools (Claude, Grok, Nous-style installers).
/// Shows version info + starts a download with progress.
struct UpdateAvailableView: View {
    let currentVersion: String
    let newVersion: String
    let downloadURL: URL
    let onInstall: (URL) -> Void
    let onLater: () -> Void

    @State private var isDownloading = false
    @State private var downloadProgress: Double = 0.0
    @State private var downloadedFileURL: URL?
    @State private var downloadError: String?
    @State private var downloadTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            VStack(spacing: 6) {
                Text("Update Available")
                    .font(.title2.bold())

                Text("Lumina \(newVersion) is now available")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("You are currently on \(currentVersion)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("This update includes the latest features and fixes.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isDownloading || downloadedFileURL != nil {
                let progress = downloadedFileURL == nil ? downloadProgress : 1.0
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                    Text(downloadedFileURL == nil ? "Downloading..." : "Download complete — ready to install")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let downloadError {
                Text(downloadError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 12) {
                Button("Later", action: onLater)
                    .buttonStyle(.bordered)

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
                    } else {
                        Text(downloadedFileURL == nil ? "Download & Install" : "Install Update")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isDownloading && downloadedFileURL == nil)
            }
        }
        .padding(28)
        .frame(width: 420)
        .onDisappear {
            // Don't let an orphaned download keep running (and possibly call onInstall)
            // after the sheet is gone.
            downloadTask?.cancel()
            downloadTask = nil
        }
    }

    private func startDownload() {
        isDownloading = true
        downloadProgress = 0
        downloadError = nil

        downloadTask = Task {
            do {
                // Stream to disk — URLSession.download never holds the whole DMG in memory
                // (the old data(from:) approach buffered multi-hundred-MB updates in RAM).
                let (fileURL, _) = try await URLSession.shared.download(from: downloadURL)

                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("Lumina-Update-\(UUID().uuidString).dmg")
                try FileManager.default.moveItem(at: fileURL, to: tempURL)

                await MainActor.run {
                    downloadProgress = 1.0
                    downloadedFileURL = tempURL
                    isDownloading = false
                    // Deliberately NOT auto-installing: the user confirms via "Install Update".
                }
            } catch is CancellationError {
                await MainActor.run { isDownloading = false }
            } catch {
                await MainActor.run {
                    isDownloading = false
                    downloadError = "Download failed: \(error.localizedDescription). Opening the release page instead."
                    NSWorkspace.shared.open(downloadURL)
                }
            }
        }
    }
}
