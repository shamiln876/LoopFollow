// LoopFollow
// PlateScan.swift

import Foundation

/// Photo suggestions carry catalog IDs and portion multipliers, never AI-generated nutrition.
struct PlateScanResponse: Codable {
    struct Suggestion: Codable {
        let label: String
        let foodID: String?
        let portions: Double?
        let uncertainty: String
    }

    let sourceSHA256: String
    let items: [Suggestion]

    func review(catalog: CarnivalFoodCatalog) throws -> [PlateScanItem] {
        guard sourceSHA256 == catalog.sourceSHA256, !items.isEmpty, items.count <= 20 else { throw PlateScanError.invalidResponse }
        guard items.allSatisfy({ !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.label.count <= 200 && $0.uncertainty.count <= 500 && ($0.portions == nil || ($0.portions!.isFinite && $0.portions! > 0 && $0.portions! <= 100)) }) else { throw PlateScanError.invalidResponse }
        return items.map { item in
            let food = catalog.foods.first { $0.id == item.foodID }
            let amount = item.portions.flatMap { $0.isFinite && $0 > 0 && $0 <= 100 ? $0 : nil }
            return PlateScanItem(label: String(item.label.prefix(200)), food: food, portions: amount ?? 1,
                                 uncertainty: item.uncertainty, confirmed: false, portionNeedsEntry: amount == nil)
        }
    }
}

struct PlateScanItem: Identifiable {
    let id = UUID()
    var label: String
    var food: CarnivalFood?
    var portions: Double
    var uncertainty: String
    var confirmed: Bool
    var portionNeedsEntry = false

    var resolved: Bool { confirmed && !portionNeedsEntry && food?.available == true && portions.isFinite && portions > 0 && portions <= 100 }
}

enum PlateScanReview {
    static func meal(_ items: [PlateScanItem], catalog: CarnivalFoodCatalog) -> CarnivalMeal? {
        guard !items.isEmpty, items.count <= 20, items.allSatisfy(\.resolved) else { return nil }
        var merged: [CarnivalMeal.Item] = []
        for item in items {
            guard let food = item.food, catalog.foods.contains(food) else { return nil }
            if let i = merged.firstIndex(where: { $0.food.id == food.id }) { merged[i].portions += item.portions }
            else { merged.append(.init(food: food, portions: item.portions)) }
        }
        let meal = CarnivalMeal(sourceFilename: catalog.sourceFilename, sourceSHA256: catalog.sourceSHA256, items: merged)
        return meal.complete ? meal : nil
    }
}

enum PlateScanError: LocalizedError {
    case configuration, invalidResponse, service
    var errorDescription: String? {
        switch self {
        case .configuration: return "Photo analysis needs a configured HTTPS scanner service and access token. The manual food guide remains available."
        case .invalidResponse: return "The scanner returned an incomplete or incompatible result. No meal values were changed. Try another photo or use the manual guide."
        case .service: return "Photo analysis could not finish. Check your connection and scanner service. No meal values were changed."
        }
    }
}

struct PlateScanClient {
    static func endpoint(_ text: String) -> URL? {
        guard let url = URL(string: text), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { return nil }
        return url
    }

    static func scan(jpeg: Data, endpoint: String, token: String, catalog: CarnivalFoodCatalog, transport: ((URLRequest) async throws -> (Data, URLResponse))? = nil) async throws -> [PlateScanItem] {
        guard let url = self.endpoint(endpoint), !token.isEmpty, !jpeg.isEmpty, jpeg.count <= 3_000_000 else { throw PlateScanError.configuration }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 75
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // No glucose, insulin, Nightscout data, patient identifiers or original image metadata.
        request.httpBody = try JSONSerialization.data(withJSONObject: ["image": jpeg.base64EncodedString(), "sourceSHA256": catalog.sourceSHA256])
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        let session = URLSession(configuration: configuration, delegate: NoPlateScanRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let result: (Data, URLResponse)
        if let transport { result = try await transport(request) }
        else { result = try await session.data(for: request) }
        let (data, response) = result
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count <= 100_000 else { throw PlateScanError.service }
        guard let decoded = try? JSONDecoder().decode(PlateScanResponse.self, from: data) else { throw PlateScanError.invalidResponse }
        return try decoded.review(catalog: catalog)
    }
}

private final class NoPlateScanRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_: URLSession, task _: URLSessionTask, willPerformHTTPRedirection _: HTTPURLResponse,
                    newRequest _: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
