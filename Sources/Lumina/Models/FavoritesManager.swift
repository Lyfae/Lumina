import Foundation

@MainActor
final class FavoritesManager: ObservableObject {
    static let shared = FavoritesManager()
    private let key = "Lumina.FavoriteWallpapers"

    @Published private(set) var favorites: Set<String> = []

    private init() {
        favorites = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    func toggle(_ id: String) {
        if favorites.contains(id) { favorites.remove(id) } else { favorites.insert(id) }
        UserDefaults.standard.set(Array(favorites), forKey: key)
    }

    func isFavorite(_ id: String) -> Bool { favorites.contains(id) }
}
