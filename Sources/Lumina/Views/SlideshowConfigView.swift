import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Dedicated slideshow builder presented as a sheet. Lets the user assemble an ordered
/// queue of images by dragging files onto a drop canvas, picking from the Library, or the
/// file panel — then tune the interval/transition and commit with "Save & Play". Images
/// added here are also saved to the Library so they can be reused.
struct SlideshowConfigView: View {
    let monitor: MonitorInfo
    @ObservedObject var store: WallpaperManagerStore
    var onClose: () -> Void = {}

    @State private var items: [String] = []
    @State private var interval: Double = 10
    @State private var transition: MonitorAssignment.SlideshowTransition = .fade
    @State private var isDropTargeted: Bool = false

    @StateObject private var themeManager = ThemeManager.shared

    private var libraryImages: [WallpaperManagerStore.RecentMedia] {
        store.recentMedia.filter { $0.mediaType == .image }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            LuminaDivider()

            // Queue / drop canvas (also accepts dragged image files).
            queueArea
                .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)

            if !libraryImages.isEmpty {
                LuminaDivider()
                librarySection
            }

            LuminaDivider()
            settingsBar
            LuminaDivider()
            footer
        }
        .frame(width: 560, height: 660)
        .background(Color.luminaBase)
        .tint(themeManager.current.color)
        .onAppear(perform: load)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "photo.stack.fill")
                .foregroundStyle(themeManager.current.color)
            VStack(alignment: .leading, spacing: 1) {
                Text("Configure Slideshow").font(.headline)
                Text(monitor.name).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill").font(.title2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .background(.bar)
    }

    // MARK: - Queue / Drop Canvas

    private var queueArea: some View {
        ZStack {
            if items.isEmpty {
                emptyDropState
            } else {
                queueList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isDropTargeted ? themeManager.current.color.opacity(0.10) : Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isDropTargeted ? themeManager.current.color : Color.clear,
                              style: StrokeStyle(lineWidth: 2, dash: [6]))
                .padding(8)
        )
    }

    private var emptyDropState: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.system(size: 44))
                .foregroundStyle(isDropTargeted ? themeManager.current.color : Color.secondary.opacity(0.4))
            Text("Drag & drop images here")
                .font(.callout).foregroundStyle(.secondary)
            Text("…or add them from your Library below, or with the button.")
                .font(.caption).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Button {
                addImagesViaPanel()
            } label: {
                Label("Add Images…", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private var queueList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("^[\(items.count) image](inflect: true) • drag to reorder")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("Drop more here")
                    .font(.caption2).foregroundStyle(.tertiary)
                Button("Clear All") { items.removeAll() }
                    .font(.caption2).buttonStyle(.plain).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18).padding(.vertical, 8)

            List {
                ForEach(items, id: \.self) { path in
                    SlideshowQueueRow(
                        path: path,
                        position: (items.firstIndex(of: path) ?? 0) + 1,
                        onRemove: { items.removeAll { $0 == path } }
                    )
                    .listRowBackground(Color.clear)
                }
                .onMove { from, to in items.move(fromOffsets: from, toOffset: to) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: - Library Picker

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("From your Library")
                .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                .padding(.horizontal, 18)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(libraryImages) { item in
                        let inQueue = items.contains(item.url.path)
                        Button {
                            if inQueue {
                                items.removeAll { $0 == item.url.path }
                            } else {
                                items.append(item.url.path)
                            }
                        } label: {
                            LibraryImageThumb(url: item.url, selected: inQueue,
                                              accent: themeManager.current.color)
                        }
                        .buttonStyle(.plain)
                        .help(inQueue ? "Remove from slideshow" : "Add to slideshow")
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 2)
            }
            .frame(height: 70)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Settings

    private var settingsBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Interval").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(interval))s per image")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Slider(value: $interval, in: 3...60, step: 1)
            }

            HStack {
                Text("Transition").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $transition) {
                    ForEach(MonitorAssignment.SlideshowTransition.allCases, id: \.self) { t in
                        Text(t.rawValue.capitalized).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 160)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button {
                addImagesViaPanel()
            } label: {
                Label("Add Images…", systemImage: "plus")
            }
            .buttonStyle(.bordered)

            Spacer()

            Button("Cancel", action: onClose)
                .buttonStyle(.bordered)

            Button {
                save()
            } label: {
                Label(items.isEmpty ? "Clear Slideshow" : "Save & Play",
                      systemImage: items.isEmpty ? "stop.circle" : "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
    }

    // MARK: - Actions

    private func load() {
        if let a = store.assignment(for: monitor.id) {
            items = a.slideshowItems
            interval = a.slideshowInterval
            transition = a.slideshowTransition
        }
    }

    /// Appends an image URL to the queue and saves it to the Library for reuse.
    private func addImage(_ url: URL) {
        guard Self.isImageURL(url) else { return }
        store.addMediaToLibrary(url: url)
        if !items.contains(url.path) { items.append(url.path) }
    }

    private func addImagesViaPanel() {
        let panel = NSOpenPanel()
        panel.title = "Add images to the slideshow"
        panel.message = "Images are also saved to your Library so you can reuse them."
        panel.allowedContentTypes = [.image]
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { addImage(url) }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers where provider.canLoadObject(ofClass: URL.self) {
            accepted = true
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url, url.isFileURL else { return }
                DispatchQueue.main.async { addImage(url) }
            }
        }
        return accepted
    }

    private func save() {
        // Order matters: set interval/transition before items so the live apply (triggered by
        // setSlideshowItems) uses the new timing/transition.
        store.setSlideshowInterval(for: monitor, interval: interval)
        store.setSlideshowTransition(for: monitor, transition: transition)
        store.setSlideshowItems(for: monitor, items: items)
        onClose()
    }

    private static func isImageURL(_ url: URL) -> Bool {
        if let type = UTType(filenameExtension: url.pathExtension.lowercased()) {
            return type.conforms(to: .image)
        }
        return false
    }
}

// MARK: - Queue Row

/// One image in the slideshow queue: position badge, thumbnail, filename, remove button.
private struct SlideshowQueueRow: View {
    let path: String
    let position: Int
    let onRemove: () -> Void

    @State private var thumbnail: NSImage?

    private var url: URL { URL(fileURLWithPath: (path as NSString).expandingTildeInPath) }

    var body: some View {
        HStack(spacing: 12) {
            Text("\(position)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 18)

            thumbView
                .frame(width: 64, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.luminaBorder, lineWidth: 0.5))

            Text(url.lastPathComponent)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .font(.caption)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove from slideshow")
        }
        .padding(.vertical, 4)
        .task(id: path) {
            thumbnail = await ThumbnailService.shared.smallThumbnail(for: url, mediaType: .image)
        }
    }

    @ViewBuilder private var thumbView: some View {
        if let thumbnail {
            Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fill)
        } else {
            Color.gray.opacity(0.15).overlay(ProgressView().scaleEffect(0.5))
        }
    }
}

// MARK: - Library Thumbnail

/// A small selectable Library image thumbnail used in the picker strip.
private struct LibraryImageThumb: View {
    let url: URL
    let selected: Bool
    let accent: Color

    @State private var thumbnail: NSImage?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Color.gray.opacity(0.15).overlay(ProgressView().scaleEffect(0.5))
                }
            }
            .frame(width: 92, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(selected ? accent : Color.luminaBorder, lineWidth: selected ? 2 : 0.5)
            )

            Image(systemName: selected ? "checkmark.circle.fill" : "plus.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(selected ? accent : .white)
                .background(Circle().fill(.black.opacity(0.5)))
                .padding(3)
        }
        .task(id: url.path) {
            thumbnail = await ThumbnailService.shared.smallThumbnail(for: url, mediaType: .image)
        }
    }
}
