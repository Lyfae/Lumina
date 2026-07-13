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
    @State private var kenBurnsEnabled: Bool = true
    @State private var isDropTargeted: Bool = false

    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var uiScale = UIScaleManager.shared

    private var libraryImages: [WallpaperManagerStore.RecentMedia] {
        store.recentMedia.filter { $0.mediaType == .image }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            LuminaDivider()

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
        .scaledFrame(width: 560, height: 660)
        .background(Color.luminaBase)
        .tint(themeManager.current.color)
        .onAppear(perform: load)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: DisplayScale.points(10)) {
            Image(systemName: "photo.stack.fill")
                .font(.system(size: uiScale.iconSize(.card), weight: .semibold))
                .foregroundStyle(themeManager.current.color)
            VStack(alignment: .leading, spacing: 1) {
                Text("Configure Slideshow")
                    .font(uiScale.scaledFont(15, weight: .semibold))
                Text(monitor.name)
                    .font(uiScale.scaledFont(12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: DisplayScale.points(20)))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .frame(width: uiScale.touchTarget(), height: uiScale.touchTarget())
            .contentShape(Rectangle())
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, DisplayScale.points(18))
        .padding(.vertical, DisplayScale.points(14))
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
        VStack(spacing: DisplayScale.points(12)) {
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.system(size: DisplayScale.points(44)))
                .foregroundStyle(isDropTargeted ? themeManager.current.color : Color.secondary.opacity(0.4))
            Text("Drag & drop images here")
                .font(uiScale.scaledFont(14))
                .foregroundStyle(.secondary)
            Text("…or add them from your Library below, or with the button.")
                .font(uiScale.scaledFont(12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                addImagesViaPanel()
            } label: {
                Label("Add Images…", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(uiScale.controlSize())
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DisplayScale.points(40))
    }

    private var queueList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("^[\(items.count) image](inflect: true) • drag to reorder")
                    .font(uiScale.scaledFont(12))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Drop more here")
                    .font(uiScale.scaledFont(11))
                    .foregroundStyle(.secondary)
                Button("Clear All") { items.removeAll() }
                    .font(uiScale.scaledFont(11))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, DisplayScale.points(18))
            .padding(.vertical, DisplayScale.points(8))

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
        VStack(alignment: .leading, spacing: DisplayScale.points(6)) {
            Text("From your Library")
                .font(uiScale.scaledFont(12, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, DisplayScale.points(18))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DisplayScale.points(8)) {
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
                .padding(.horizontal, DisplayScale.points(18))
                .padding(.bottom, 2)
            }
            .frame(height: DisplayScale.points(70))
        }
        .padding(.vertical, DisplayScale.points(8))
    }

    // MARK: - Settings

    private var settingsBar: some View {
        VStack(alignment: .leading, spacing: DisplayScale.points(12)) {
            VStack(alignment: .leading, spacing: 4) {
                LuminaSliderLabel(title: "Interval", value: "\(Int(interval))s per image")
                LuminaSlider(value: $interval, range: 3...60, step: 1)
            }

            HStack {
                Text("Transition")
                    .font(uiScale.scaledFont(13, weight: .medium))
                Spacer()
                Picker("", selection: $transition) {
                    ForEach(MonitorAssignment.SlideshowTransition.allCases, id: \.self) { t in
                        Text(t.rawValue.capitalized).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(uiScale.controlSize())
                .scaledFrame(width: 160)
            }

            Toggle(isOn: $kenBurnsEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Ken Burns effect", systemImage: "camera.aperture")
                        .font(uiScale.scaledFont(13, weight: .medium))
                    Text("Slow cinematic pan & zoom on each image — like a documentary.")
                        .font(uiScale.scaledFont(11))
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .controlSize(uiScale.controlSize())
            .accessibilityLabel("Ken Burns effect")
            .accessibilityHint("Enable slow pan and zoom animation on slideshow images")
        }
        .padding(.horizontal, DisplayScale.points(18))
        .padding(.vertical, DisplayScale.points(14))
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
            .controlSize(uiScale.controlSize())

            Spacer()

            Button("Cancel", action: onClose)
                .buttonStyle(.bordered)
                .controlSize(uiScale.controlSize())

            Button {
                save()
            } label: {
                Label(items.isEmpty ? "Clear Slideshow" : "Save & Play",
                      systemImage: items.isEmpty ? "stop.circle" : "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(uiScale.controlSize())
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, DisplayScale.points(18))
        .padding(.vertical, DisplayScale.points(14))
    }

    // MARK: - Actions

    private func load() {
        if let a = store.assignment(for: monitor.id) {
            items = a.slideshowItems
            interval = a.slideshowInterval
            transition = a.slideshowTransition
            kenBurnsEnabled = a.slideshowKenBurnsEnabled
        }
    }

    /// Appends an image URL to the queue and saves it to the Library for reuse.
    private func addImage(_ url: URL) {
        guard Self.isImageURL(url) else { return }
        guard MediaAccessPolicy.accept(url) else { return }
        store.addMediaToLibrary(url: url, enforceAccessPolicy: false)
        if !items.contains(url.path) { items.append(url.path) }
    }

    private func addImagesViaPanel() {
        let urls = MediaAccessPolicy.runWallpaperPicker(
            title: "Add images to the slideshow",
            message: "Images are also saved to your Library so you can reuse them.",
            allowedTypes: [.image],
            allowsMultipleSelection: true
        )
        for url in urls {
            store.addMediaToLibrary(url: url, enforceAccessPolicy: false)
            if !items.contains(url.path) { items.append(url.path) }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers {
            // Finder exposes dropped files as `public.file-url` Data, which
            // loadObject(ofClass: URL.self) often fails to see — read the raw
            // type identifier and decode the URL ourselves.
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                accepted = true
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    let url: URL?
                    if let data = item as? Data {
                        url = URL(dataRepresentation: data, relativeTo: nil)
                    } else if let u = item as? URL {
                        url = u
                    } else {
                        url = nil
                    }
                    guard let url, url.isFileURL else { return }
                    DispatchQueue.main.async { addImage(url) }
                }
            } else if provider.canLoadObject(ofClass: URL.self) {
                accepted = true
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, url.isFileURL else { return }
                    DispatchQueue.main.async { addImage(url) }
                }
            }
        }
        return accepted
    }

    private func save() {
        // Order matters: set interval/transition before items so the live apply (triggered by
        // setSlideshowItems) uses the new timing/transition.
        store.setSlideshowInterval(for: monitor, interval: interval)
        store.setSlideshowTransition(for: monitor, transition: transition)
        store.setSlideshowKenBurns(for: monitor, enabled: kenBurnsEnabled)
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

    @StateObject private var uiScale = UIScaleManager.shared
    @State private var thumbnail: NSImage?

    private var url: URL { URL(fileURLWithPath: (path as NSString).expandingTildeInPath) }

    var body: some View {
        HStack(spacing: DisplayScale.points(12)) {
            Text("\(position)")
                .font(uiScale.scaledFont(12).monospacedDigit())
                .foregroundStyle(.secondary)
                .scaledFrame(width: 18)

            thumbView
                .scaledFrame(width: 64, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: DisplayScale.points(5)))
                .overlay(
                    RoundedRectangle(cornerRadius: DisplayScale.points(5))
                        .strokeBorder(Color.luminaBorder, lineWidth: 0.5)
                )

            Text(url.lastPathComponent)
                .font(uiScale.scaledFont(13, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .font(uiScale.scaledFont(11))

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: DisplayScale.points(16)))
                    .foregroundStyle(.secondary)
                    .frame(width: uiScale.touchTarget(), height: uiScale.touchTarget())
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Remove from slideshow")
            .accessibilityLabel("Remove from slideshow")
        }
        .padding(.vertical, DisplayScale.points(4))
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
            .scaledFrame(width: 92, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: DisplayScale.points(6)))
            .overlay(
                RoundedRectangle(cornerRadius: DisplayScale.points(6))
                    .strokeBorder(selected ? accent : Color.luminaBorder, lineWidth: selected ? 2 : 0.5)
            )

            Image(systemName: selected ? "checkmark.circle.fill" : "plus.circle.fill")
                .font(.system(size: DisplayScale.points(14)))
                .foregroundStyle(selected ? accent : .white)
                .background(Circle().fill(.black.opacity(0.5)))
                .padding(DisplayScale.points(3))
        }
        .task(id: url.path) {
            thumbnail = await ThumbnailService.shared.smallThumbnail(for: url, mediaType: .image)
        }
    }
}
