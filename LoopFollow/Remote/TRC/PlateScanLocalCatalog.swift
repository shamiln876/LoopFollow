// LoopFollow
// PlateScanLocalCatalog.swift

import Foundation

/// Bounded local lookup for the on-device model. It never returns nutrition.
enum PlateScanLocalCatalog {
    struct Match: Encodable {
        let id: String
        let name: String
        let venue: String
        let portion: String
    }

    static func matches(_ query: String, catalog: CarnivalFoodCatalog) -> [Match] {
        let ignored: Set<String> = ["a", "an", "the", "and", "with", "of", "on", "some", "food", "plate", "portion"]
        let words = Set(normalize(String(query.prefix(80))).split(separator: " ").map(String.init)).subtracting(ignored).filter { $0.count > 1 }
        guard !words.isEmpty else { return [] }
        return catalog.foods.compactMap { food -> (CarnivalFood, Int)? in
            let name = normalize(food.name)
            let score = words.reduce(0) { $0 + (name.contains($1) ? 1 : 0) }
            return score > 0 ? (food, score) : nil
        }.sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            return ($0.0.name, $0.0.venue, $0.0.id) < ($1.0.name, $1.0.venue, $1.0.id)
        }.prefix(4).map { Match(id: $0.0.id, name: $0.0.name, venue: $0.0.venue, portion: $0.0.portion) }
    }

    /// An ID must have been returned by the local lookup for this photo session.
    /// An invented/unoffered match stays visible and unresolved, never zero carbs.
    static func ground(_ response: PlateScanResponse, offeredIDs: Set<String>) -> PlateScanResponse {
        PlateScanResponse(sourceSHA256: response.sourceSHA256, items: response.items.map { item in
            guard let id = item.foodID, offeredIDs.contains(id) else {
                return .init(label: item.label, foodID: nil, portions: nil,
                             uncertainty: String(("No verified catalog match. " + item.uncertainty).prefix(500)))
            }
            return item
        })
    }

    private static func normalize(_ value: String) -> String {
        String(value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " })
    }
}
