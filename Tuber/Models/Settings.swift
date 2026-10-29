import Foundation

enum Settings {
    static let skipCategoriesKey = "skipCategories"
    static let defaultSkipCategories = "sponsor,selfpromo,interaction"
    static let allCategories = ["sponsor", "selfpromo", "interaction", "intro", "outro", "preview", "music_offtopic", "filler"]

    static var skipCategories: [String] {
        (UserDefaults.standard.string(forKey: skipCategoriesKey) ?? defaultSkipCategories)
            .split(separator: ",").map(String.init)
    }
}
