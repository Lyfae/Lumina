import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Dedicated slideshow builder presented as a sheet.
struct SlideshowConfigView: View {
    let monitor: MonitorInfo
    @ObservedObject var store: WallpaperManagerStore
    var onClose: () -> Void = {}

    @State private var items: [String] = []
    @State private var interval: Double = 10
    @State private var transition: SlideshowTransition = .fade
    @State private var kenBurnsEnabled: Bool = true
    @State private var isDropTargeted: Bool = false

    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var uiScale = UIScaleManager.shared

    private var libraryImages: [WallpaperManagerStore.RecentMedia] {
        store.recentMedia.filter { $0.mediaType == .image }
    }

    var body: some View {
        VStack(spacing: 0) {
            LuminaSheetHeader(
                icon: "photo.stack.fill",
                title: "Slideshow",
                subtitle: monitor.name,
                onClose: onClose
            )

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
        .clipShape(RoundedRectangle(cornerRadius: LuminaRadius.floating, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LuminaRadius.floating, style: .continuous)
                .strokeBorder(Color.luminaBorder, lineWidth: 1)
        )
        .tint(themeManager.current.color)
        .onAppear(perform: load)
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
        .background(isDropTargeted ? themeManager.current.color.opacity(0.08) : Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: LuminaRadius.panel, style: .continuous)
                .strokeBorder(
                    isDropTargeted ? themeManager.current.color : Color.clear,
                    style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                )
                .padding(LuminaSpace.sm)
        )
    }

    private var emptyDropState: some View {
        LuminaEmptyState(
            icon: "square.and.arrow.down.on.square",
            title: "Drop images here",
            message: "Or pick some from your library below."
        ) {
            Button {
                addImagesViaPanel()
            } label: {
                Label("Add Images…", systemImage: "plus")
            }
            .buttonStyle(LuminaProminentButtonStyle())
            .controlSize(uiScale.controlSize())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(LuminaSpace.xxxl)
    }

    private var queueList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("^[\(items.count) image](inflect: true) · drag to reorder")
                    .font(uiScale.font(.callout))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Remove All") { items.removeAll() }
                    .buttonStyle(LuminaSecondaryButtonStyle(destructive: true))
                    .controlSize(.small)
            }
            .padding(.horizontal, LuminaSpace.xl)
            .padding(.vertical, LuminaSpace.sm)

            List {
                ForEach(items, id: \.self) { path in
                    SlideshowQueueRow(
                        path: path,
                        position: (items.firstIndex(of: path) ?? 0) + 1,
                        onRemove: { items.removeAll { $0 == path } }
                    )
                    .listRowBackground(Color.clear)
                    .frame(minHeight: LuminaMetrics.queueRow)
                }
                .onMove { from, to in items.move(fromOffsets: from, toOffset: to) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: - Library Picker

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: LuminaSpace.tight) {
            Text("From your library")
                .font(uiScale.font(.callout).weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, LuminaSpace.xl)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: LuminaSpace.sm) {
                    ForEach(libraryImages) { item in
                        let inQueue = items.contains(item.url.path)
                        Button {
                            if inQueue {
                                items.removeAll { $0 == item.url.path }
                            } else {
                                items.append(item.url.path)
                            }
                        } label: {
                            LibraryImageThumb(
                                url: item.url,
                                selected: inQueue,
                                accent: themeManager.current.color
                            )
                        }
                        .buttonStyle(LuminaPressableButtonStyle())
                        .help(inQueue ? "Remove from slideshow" : "Add to slideshow")
                    }
                }
                .padding(.horizontal, LuminaSpace.xl)
                .padding(.bottom, LuminaSpace.hair)
            }
            .frame(height: LuminaMetrics.libraryStripHeight)
        }
        .padding(.vertical, LuminaSpace.sm)
    }

    // MARK: - Settings

    private var settingsBar: some View {
        VStack(alignment: .leading, spacing: LuminaSpace.md) {
            VStack(alignment: .leading, spacing: LuminaSpace.xs) {
                LuminaSliderLabel(
                    title: "Show each image for",
                    value: "\(Int(interval)) s"
                )
                LuminaSlider(value: $interval, range: 3...60, step: 1, label: "Show each image for")
            }

            HStack {
                Text("Transition")
                    .font(uiScale.font(.bodyStrong))
                Spacer()
                LuminaSegmentedPicker(
                    selection: $transition,
                    options: SlideshowTransition.allCases.map {
                        LuminaSegmentedOption($0, title: $0.rawValue.capitalized)
                    }
                )
                .scaledFrame(width: 180)
            }

            Toggle(isOn: $kenBurnsEnabled) {
                VStack(alignment: .leading, spacing: LuminaSpace.hair) {
                    Text("Pan and zoom")
                        .font(uiScale.font(.bodyStrong))
                    Text("Slowly moves across each image.")
                        .font(uiScale.font(.caption))
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .controlSize(uiScale.controlSize())
            .accessibilityLabel("Pan and zoom")
        }
        .padding(.horizontal, LuminaSpace.xl)
        .padding(.vertical, LuminaSpace.lg)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button {
                addImagesViaPanel()
            } label: {
                Label("Add Images…", systemImage: "plus")
            }
            .buttonStyle(LuminaSecondaryButtonStyle())
            .controlSize(uiScale.controlSize())

            Spacer()

            Button("Cancel", action: onClose)
                .buttonStyle(LuminaSecondaryButtonStyle())
                .controlSize(uiScale.controlSize())

            if items.isEmpty {
                Button("Remove Slideshow") { save() }
                    .buttonStyle(LuminaSecondaryButtonStyle(destructive: true))
                    .controlSize(uiScale.controlSize())
            } else {
                Button("Save") { save() }
                    .buttonStyle(LuminaProminentButtonStyle())
                    .controlSize(uiScale.controlSize())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, LuminaSpace.xl)
        .padding(.vertical, LuminaSpace.lg)
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

    private func addImage(_ url: URL) {
        guard Self.isImageURL(url) else { return }
        guard MediaAccessPolicy.accept(url) else { return }
        store.addMediaToLibrary(url: url, enforceAccessPolicy: false)
        if !items.contains(url.path) { items.append(url.path) }
    }

    private func addImagesViaPanel() {
        let urls = MediaAccessPolicy.runWallpaperPicker(
            title: "Add Images",
            message: "Images are also added to your library.",
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

private struct SlideshowQueueRow: View {
    let path: String
    let position: Int
    let onRemove: () -> Void

    @StateObject private var uiScale = UIScaleManager.shared
    @State private var thumbnail: NSImage?

    private var url: URL { URL(fileURLWithPath: (path as NSString).expandingTildeInPath) }
    private var filename: String { url.lastPathComponent }

    var body: some View {
        HStack(spacing: LuminaSpace.md) {
            Text("\(position)")
                .font(uiScale.font(.callout).monospacedDigit())
                .foregroundStyle(.secondary)
                .scaledFrame(width: DisplayScale.points(18))

            thumbView
                .scaledFrame(width: 64, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: LuminaRadius.small, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: LuminaRadius.small, style: .continuous)
                        .strokeBorder(Color.luminaBorder, lineWidth: 1)
                )

            Text(filename)
                .font(uiScale.font(.body).weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .font(uiScale.font(.caption))
                .accessibilityHidden(true)

            Button(action: onRemove) {
                Image(systemName: "xmark")
            }
            .buttonStyle(LuminaIconButtonStyle(size: .compact))
            .accessibilityLabel("Remove \(filename)")
        }
        .padding(.vertical, LuminaSpace.xs)
        .task(id: path) {
            thumbnail = await ThumbnailService.shared.smallThumbnail(for: url, mediaType: .image)
        }
    }

    @ViewBuilder private var thumbView: some View {
        if let thumbnail {
            Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fill)
        } else {
            RoundedRectangle(cornerRadius: LuminaRadius.small, style: .continuous)
                .fill(Color.luminaFill)
                .overlay(ProgressView().controlSize(.small))
        }
    }
}

// MARK: - Library Thumbnail

private struct LibraryImageThumb: View {
    let url: URL
    let selected: Bool
    let accent: Color

    @StateObject private var uiScale = UIScaleManager.shared
    @State private var thumbnail: NSImage?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fill)
                } else {
                    RoundedRectangle(cornerRadius: LuminaRadius.small, style: .continuous)
                        .fill(Color.luminaFill)
                        .overlay(ProgressView().controlSize(.small))
                }
            }
            .scaledFrame(width: 92, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: LuminaRadius.small, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: LuminaRadius.small, style: .continuous)
                    .strokeBorder(selected ? accent : Color.luminaBorder, lineWidth: selected ? 2 : 1)
            )

            Image(systemName: selected ? "checkmark.circle.fill" : "plus.circle.fill")
                .font(.system(size: uiScale.iconSize(.card)))
                .foregroundStyle(selected ? accent : .white)
                .background(
                    Circle().fill(selected ? Color.luminaCard : Color.luminaOverlay)
                )
                .padding(LuminaSpace.hair)
        }
        .task(id: url.path) {
            thumbnail = await ThumbnailService.shared.smallThumbnail(for: url, mediaType: .image)
        }
    }
}
