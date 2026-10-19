// LoopFollow
// CarnivalFoodGuideView.swift

import SwiftUI

struct CarnivalFoodGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var venue = ""
    @State private var tab = 0
    @State private var showPhotoScanner = false
    @State private var acceptedPhotoMeal: CarnivalMeal?
    @State private var items: [CarnivalMeal.Item]
    private let catalog: Result<CarnivalFoodCatalog, Error>
    private let use: (CarnivalMeal) -> Void

    init(initialMeal: CarnivalMeal? = nil, catalog: Result<CarnivalFoodCatalog, Error> = CarnivalFoodCatalog.bundled, use: @escaping (CarnivalMeal) -> Void) {
        self.catalog = catalog
        self.use = use
        _items = State(initialValue: initialMeal?.items ?? [])
        _tab = State(initialValue: initialMeal?.items.isEmpty == false ? 1 : 0)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch catalog {
                case let .success(guide): content(guide)
                case .failure:
                    ContentUnavailableView("Food guide unavailable", systemImage: "fork.knife", description: Text("Use manual carb entry until the guide is restored."))
                }
            }
            .navigationTitle("Carnival food guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }

    private func content(_ guide: CarnivalFoodCatalog) -> some View {
        Form {
            Section {
                Picker("Food guide", selection: $tab) {
                    Text("Find food").tag(0)
                    Text("My plate (\(items.count))").tag(1)
                }.pickerStyle(.segmented)
                Text("Offline guide · \(guide.foods.count) foods. All nutrition values are estimates; check the listed portion.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if tab == 0 {
                searchSections(guide)
            } else {
                plateSections(guide)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .sheet(isPresented: $showPhotoScanner, onDismiss: {
            if let meal = acceptedPhotoMeal { acceptedPhotoMeal = nil; use(meal); dismiss() }
        }) {
            PlateScannerView(catalog: guide) { meal in acceptedPhotoMeal = meal }
        }
    }

    @ViewBuilder
    private func searchSections(_ guide: CarnivalFoodCatalog) -> some View {
        Section {
            Button { showPhotoScanner = true } label: { Label("Take / upload plate photo (optional)", systemImage: "camera") }
                .accessibilityIdentifier("carnival-photo-scanner")
        }
        Section("Search food or venue") {
            TextField("Rice, nuggets, burger…", text: $query).autocorrectionDisabled()
                .accessibilityLabel("Search Carnival foods")
            Picker("Venue", selection: $venue) {
                Text("All venues").tag("")
                ForEach(guide.venues, id: \.self) { Text($0).tag($0) }
            }
        }
        let matches = guide.search(query, venue: venue)
        Section("\(matches.count) matches") {
            if matches.isEmpty { Text("No match. Try another food name or venue. Unmatched foods have no carb estimate.") }
            ForEach(Array(matches.prefix(100))) { food in
                NavigationLink {
                    CarnivalFoodPortionView(food: food, action: "Add to plate") { amount in
                        if let index = items.firstIndex(where: { $0.id == food.id }) {
                            items[index].portions += amount
                        } else { items.append(.init(food: food, portions: amount)) }
                        tab = 1
                    }
                } label: { foodLabel(food) }
            }
            if matches.count > 100 { Text("Showing the first 100. Refine the search or choose a venue.").font(.footnote) }
        }
    }

    @ViewBuilder
    private func foodLabel(_ food: CarnivalFood) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(food.name).font(.headline)
            Text(food.venue).font(.caption).foregroundStyle(.secondary)
            Text(food.portion).font(.subheadline)
            if let carbs = food.carbs {
                Text("Estimated carbs: \(CarnivalNumber.text(carbs)) g").font(.subheadline)
            } else { Text("Nutrition unavailable").font(.subheadline).foregroundStyle(.orange) }
        }.padding(.vertical, 3)
    }

    @ViewBuilder
    private func plateSections(_ guide: CarnivalFoodCatalog) -> some View {
        let meal = CarnivalMeal(sourceFilename: guide.sourceFilename, sourceSHA256: guide.sourceSHA256, items: items)
        Section("Your portions") {
            if items.isEmpty { Text("Find a food, check its base portion and add the amount eaten.") }
            ForEach(items) { item in
                NavigationLink {
                    CarnivalFoodPortionView(food: item.food, initialPortions: item.portions, action: "Save portion") { amount in
                        if let index = items.firstIndex(where: { $0.id == item.id }) { items[index].portions = amount }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.food.name).font(.headline)
                        Text("\(CarnivalNumber.text(item.portions)) × \(item.food.portion)").font(.subheadline)
                        if !item.food.available { Text("Nutrition unavailable").foregroundStyle(.orange) }
                        if !item.validQuantity { Text("Check the quantity").foregroundStyle(.orange) }
                    }
                }
            }.onDelete { items.remove(atOffsets: $0) }
            if !items.isEmpty { Text("Tap a food to change its portion. Swipe left to remove it.").font(.footnote).foregroundStyle(.secondary) }
        }
        Section("Estimated plate total") {
            if let carbs = meal.carbsForReview {
                nutrient("Total carbs", carbs, unit: "g", prominent: true)
                if let low = meal.total(\.low), let high = meal.total(\.high) {
                    Text("Planning range: \(CarnivalNumber.text(low))–\(CarnivalNumber.text(high)) g carbs. Actual food can fall outside this range.").font(.footnote)
                }
                nutrient("Protein", meal.total(\.protein), unit: "g")
                nutrient("Fat", meal.total(\.fat), unit: "g")
                nutrient("Fibre", meal.total(\.fibre), unit: "g")
                nutrient("Net carbs · reference only", meal.total(\.netCarbs), unit: "g")
                Text("Uses the guide's rounded values and your selected portions. Total carbs are used for the review; protein and fat do not add insulin.").font(.footnote).foregroundStyle(.secondary)
                Button("Use \(CarnivalNumber.text(carbs)) g in meal review") { use(meal); dismiss() }
                    .font(.headline)
                    .accessibilityIdentifier("carnival-use-total")
            } else if !items.isEmpty {
                Text("Carb total incomplete").font(.headline).foregroundStyle(.orange)
                Text("Every food needs an available estimate and a valid quantity. Unknown nutrition is not counted as zero. A plate can contain up to 20 different foods.")
            } else { Text("Add foods to see the estimated total.") }
        }
        Section("Guide limitations") {
            Text(guide.notice).font(.footnote)
            Text("Quarter-plate references assume a depth and volume; a quarter of a plate is not a fixed weight. Sides and sauces may need separate entries. Food flags do not predict glucose timing.").font(.footnote)
        }
    }

    private func nutrient(_ label: String, _ value: Double?, unit: String, prominent: Bool = false) -> some View {
        HStack { Text(label); Spacer(); Text(value.map { "\(CarnivalNumber.text($0)) \(unit)" } ?? "Unavailable").monospacedDigit() }
            .font(prominent ? .title3.weight(.semibold) : .body)
    }
}

private struct CarnivalFoodPortionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var amount: String
    let food: CarnivalFood
    let action: String
    let save: (Double) -> Void

    init(food: CarnivalFood, initialPortions: Double = 1, action: String, save: @escaping (Double) -> Void) {
        self.food = food
        self.action = action
        self.save = save
        _amount = State(initialValue: CarnivalNumber.text(initialPortions))
    }

    private var quantity: Double? {
        guard let value = Double(amount.replacingOccurrences(of: ",", with: ".")), value.isFinite, value > 0, value <= 100 else { return nil }
        return value
    }

    var body: some View {
        Form {
            Section("Listed base portion") {
                Text(food.name).font(.headline)
                Text(food.venue).foregroundStyle(.secondary)
                Text(food.portion)
            }
            Section("Amount eaten") {
                HStack {
                    Text("Number of base portions")
                    TextField("Amount", text: $amount).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        .accessibilityLabel("Number of listed base portions")
                }
                HStack {
                    ForEach([0.25, 0.5, 1.0, 2.0], id: \.self) { value in
                        Button(CarnivalNumber.text(value)) { amount = CarnivalNumber.text(value) }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("\(CarnivalNumber.text(value)) base portions")
                    }
                }
                Text("0.5 means half the listed portion. If the base is one nugget, enter 6 for six nuggets. Check the base above before counting pieces.").font(.footnote)
                if quantity == nil { Text("Enter a quantity greater than zero and at most 100 base portions.").foregroundStyle(.orange) }
            }
            Section("Estimated nutrition for this amount") {
                if !food.available { Text("Nutrition is unavailable. Adding this food makes the plate's carb total incomplete.").foregroundStyle(.orange) }
                row("Total carbs", food.carbs, unit: "g")
                row("Protein", food.protein, unit: "g")
                row("Fat", food.fat, unit: "g")
                row("Fibre", food.fibre, unit: "g")
                row("Net carbs · reference only", food.netCarbs, unit: "g")
                if let low = food.low, let high = food.high, let quantity {
                    Text("Carb planning range: \(CarnivalNumber.text(low * quantity))–\(CarnivalNumber.text(high * quantity)) g. Not guaranteed bounds.").font(.footnote)
                }
            }
            Section {
                Button(action) { if let quantity { save(quantity); dismiss() } }.disabled(quantity == nil)
            }
            Section("Source and assumptions") {
                Text("Supplied guide · page \(food.sourcePage) · \(food.id)").font(.footnote)
                Text(food.notes).font(.footnote).foregroundStyle(.secondary)
                if let url = URL(string: food.sourceURL) { Link("Menu or food reference", destination: url) }
            }
        }
        .navigationTitle("Check portion")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Hide keyboard") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) } } }
    }

    private func row(_ label: String, _ value: Double?, unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value.flatMap { value in quantity.map { "\(CarnivalNumber.text(value * $0)) \(unit)" } } ?? "Unavailable").monospacedDigit()
        }
    }
}
