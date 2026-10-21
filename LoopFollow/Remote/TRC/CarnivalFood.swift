// LoopFollow
// CarnivalFood.swift

import Foundation

struct CarnivalFood: Codable, Equatable, Identifiable {
    enum Nutrition: String, Codable { case estimate, unavailable }
    let id: String
    let venue: String
    let name: String
    let portion: String
    let carbs: Double?
    let netCarbs: Double?
    let fibre: Double?
    let protein: Double?
    let fat: Double?
    let calories: Double?
    let low: Double?
    let high: Double?
    let nutrition: Nutrition
    let notes: String
    let sourcePage: Int
    let sourceNumber: String
    let sourceURL: String

    var available: Bool { nutrition == .estimate && [carbs, netCarbs, fibre, protein, fat, calories, low, high].allSatisfy { $0.map { $0.isFinite && $0 >= 0 } == true } }
}

struct CarnivalFoodCatalog: Decodable {
    let schemaVersion: Int
    let sourceFilename: String
    let sourceSHA256: String
    let sailingDate: String
    let notice: String
    let foods: [CarnivalFood]

    enum CatalogError: LocalizedError {
        case invalid
        var errorDescription: String? { "The food guide could not be verified. Use manual carb entry until the guide is restored." }
    }

    static let bundled: Result<CarnivalFoodCatalog, Error> = Result {
        guard let url = Bundle.main.url(forResource: "CarnivalFoodGuide", withExtension: "json") else { throw CatalogError.invalid }
        return try decode(Data(contentsOf: url))
    }

    static func decode(_ data: Data) throws -> Self {
        let catalog = try JSONDecoder().decode(Self.self, from: data)
        guard catalog.schemaVersion == 1, catalog.sourceSHA256.count == 64, !catalog.sourceFilename.isEmpty,
              !catalog.foods.isEmpty, catalog.foods.count <= 5000, Set(catalog.foods.map(\.id)).count == catalog.foods.count
        else { throw CatalogError.invalid }
        for food in catalog.foods {
            guard !food.id.isEmpty, !food.name.isEmpty, !food.venue.isEmpty, !food.portion.isEmpty, food.sourcePage > 0,
                  let url = URL(string: food.sourceURL), ["https", "http"].contains(url.scheme), url.host != nil
            else { throw CatalogError.invalid }
            if food.nutrition == .estimate {
                guard food.available, let low = food.low, let high = food.high, let carbs = food.carbs, low <= carbs, carbs <= high else { throw CatalogError.invalid }
            } else if [food.carbs, food.netCarbs, food.fibre, food.protein, food.fat, food.calories, food.low, food.high].contains(where: { $0 != nil }) {
                throw CatalogError.invalid
            }
        }
        return catalog
    }

    var venues: [String] { Set(foods.map(\.venue)).sorted() }

    func search(_ query: String, venue: String = "") -> [CarnivalFood] {
        let words = Self.normalized(query).split(separator: " ")
        return foods.filter { food in
            guard venue.isEmpty || food.venue == venue else { return false }
            let text = Self.normalized("\(food.name) \(food.venue) \(food.portion)")
            return words.allSatisfy { text.contains($0) }
        }.sorted { ($0.name, $0.venue, $0.id) < ($1.name, $1.venue, $1.id) }
    }

    private static func normalized(_ text: String) -> String {
        String(text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")).unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " })
    }
}

struct CarnivalMeal: Codable, Equatable {
    struct Item: Codable, Equatable, Identifiable {
        var id: String { food.id }
        let food: CarnivalFood
        var portions: Double
        var validQuantity: Bool { portions.isFinite && portions > 0 && portions <= 100 }
    }

    let sourceFilename: String
    let sourceSHA256: String
    var items: [Item]

    var complete: Bool { !items.isEmpty && items.count <= 20 && Set(items.map(\.id)).count == items.count && items.allSatisfy { $0.validQuantity && $0.food.available } }

    func total(_ key: KeyPath<CarnivalFood, Double?>) -> Double? {
        guard complete else { return nil }
        let sum = items.reduce(0.0) { $0 + ($1.food[keyPath: key] ?? .nan) * $1.portions }
        return sum.isFinite && sum >= 0 ? sum : nil
    }

    var carbsForReview: Double? { total(\.carbs).map { ($0 * 10).rounded() / 10 } }
}

enum CarnivalNumber {
    static func text(_ value: Double) -> String {
        guard value.isFinite else { return "Unavailable" }
        if value.rounded() == value { return String(format: "%.0f", value) }
        return String(format: "%.3f", value).replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
    }
}
