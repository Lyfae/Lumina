import SwiftUI

/// Update sheet with download progress — matches Lumina theme and fixed window sizing.
struct UpdateAvailableView: View {
    let currentVersion: String
    let newVersion: String
    let downloadURL: URL
    let onInstall: (URL) -> Void
    let onLater: () -> Void

    @StateObject private var themeManager = ThemeManager.shared
    @State private var isDownloading = false
    @State private var downloadProgress: Double = 0.0
    @State private var downloadedFileURL: URL?
    @State private var downloadError: String?
    @State private var downloadTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: DisplayScale.points(20)) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: DisplayScale.points(48)))
                .foregroundStyle(themeManager.current.color)

            VStack(spacing: DisplayScale.points(6)) {
                Text("Update Available")
                    .font(.system(size: DisplayScale.points(20), weight: .bold))
                Text("Lumina \(newVersion) is now available")
                    .font(.system(size: DisplayScale.points(15), weight: .medium))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: DisplayScale.points(4)) {
                Text("You are currently on \(currentVersion)")
                    .font(.system(size: DisplayScale.points(13)))
                    .foregroundStyle(.secondary)
                Text("This update includes the latest features and fixes.")
                    .font(.system(size: DisplayScale.points(13)))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isDownloading || downloadedFileURL != nil {
                let progress = downloadedFileURL == nil ? downloadProgress : 1.0
                VStack(alignment: .leading, spacing: DisplayScale.points(6)) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                    Text(downloadedFileURL == nil ? "Downloading…" : "Download complete — ready to install")
                        .font(.system(size: DisplayScale.points(11)))
                        .foregroundStyle(.secondary)
                }
            }

            if let downloadError {
                Text(downloadError)
                    .font(.system(size: DisplayScale.points(11)))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: DisplayScale.points(12)) {
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
        .padding(DisplayScale.points(28))
        .scaledFrame(width: 420, height: 380)
        .background(Color.luminaBase)
        .tint(themeManager.current.color)
        .onDisappear {
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
                let (fileURL, _) = try await URLSession.shared.download(from: downloadURL)

                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("Lumina-Update-\(UUID().uuidString).dmg")
                try FileManager.default.moveItem(at: fileURL, to: tempURL)

                await MainActor.run {
                    downloadProgress = 1.0
                    downloadedFileURL = tempURL
                    isDownloading = false
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
