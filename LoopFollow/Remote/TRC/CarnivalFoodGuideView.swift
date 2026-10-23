// LoopFollow
// CarnivalFoodGuideView.swift

import SwiftUI

struct CarnivalFoodGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var venue = ""
    @State private var tab = 0
    @State private var quickCategory: CarnivalQuickCategory = .starches
    @State private var showPhotoScanner = false
    @State private var acceptedPhotoMeal: CarnivalMeal?
    @State private var items: [CarnivalMeal.Item]
    private let catalog: Result<CarnivalFoodCatalog, Error>
    private let use: (CarnivalMeal) -> Void

    init(initialMeal: CarnivalMeal? = nil, catalog: Result<CarnivalFoodCatalog, Error> = CarnivalFoodCatalog.bundled, use: @escaping (CarnivalMeal) -> Void) {
        self.catalog = catalog
        self.use = use
        _items = State(initialValue: initialMeal?.items ?? [])
        _tab = State(initialValue: initialMeal?.items.isEmpty == false ? 2 : 0)
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
                    Text("Quick add").tag(0)
                    Text("Search").tag(1)
                    Text("Plate (\(items.count))").tag(2)
                }.pickerStyle(.segmented)
                Text("Offline guide · \(guide.foods.count) foods. All nutrition values are estimates; check the listed portion.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if tab == 0 {
                quickSections(guide)
            } else if tab == 1 {
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
    private func quickSections(_ guide: CarnivalFoodCatalog) -> some View {
        Section("What is on his plate?") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(CarnivalQuickCategory.allCases) { category in
                        Button(category.rawValue) { quickCategory = category }
                            .buttonStyle(.bordered)
                            .tint(quickCategory == category ? .accentColor : .secondary)
                            .accessibilityIdentifier("quick-food-category-\(category.id)")
                    }
                }
                .padding(.vertical, 3)
            }
            Text("Tap + to add a quarter cup for measured foods, or a half serving for individual items.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        let names = Set(quickCategory.foodNames)
        let matching = guide.foods.filter { $0.venue == "Lido buffet / components" && names.contains($0.name) && $0.available }
            .sorted { $0.name < $1.name }
        Section(quickCategory.rawValue) {
            ForEach(matching) { food in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(food.name).font(.subheadline.weight(.medium))
                        Text(CarnivalQuickPortion.stepLabel(for: food))
                            .font(.caption).foregroundStyle(.secondary)
                        if let amount = food.carbs {
                            Text("~\(CarnivalNumber.text(amount * CarnivalQuickPortion.step(for: food))) g per tap")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button {
                        adjustQuickFood(food, by: CarnivalQuickPortion.step(for: food))
                    } label: {
                        Image(systemName: "plus.circle.fill").font(.title2)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Add \(CarnivalQuickPortion.stepLabel(for: food)) of \(food.name)")
                }
            }
        }
        let meal = CarnivalMeal(sourceFilename: guide.sourceFilename, sourceSHA256: guide.sourceSHA256, items: items)
        Section("My plate") {
            if items.isEmpty { Text("Choose foods above to start your plate.").foregroundStyle(.secondary) }
            ForEach(items) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.food.name).font(.subheadline.weight(.medium))
                        Text(CarnivalQuickPortion.amountLabel(for: item))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let carbs = item.food.carbs {
                        Text("~\(CarnivalNumber.text(carbs * item.portions)) g")
                            .font(.subheadline).monospacedDigit()
                    }
                    Button {
                        adjustQuickFood(item.food, by: -CarnivalQuickPortion.step(for: item.food))
                    } label: {
                        Image(systemName: "minus.circle").font(.title3)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove one portion step of \(item.food.name)")
                }
            }
            if let total = meal.carbsForReview {
                HStack {
                    Text("Estimated carbs").font(.headline)
                    Spacer()
                    Text("\(CarnivalNumber.text(total)) g").font(.title3.weight(.semibold)).monospacedDigit()
                }
                Text("Approximate food-guide values, not a verified insulin dose. Your insulin entry stays separate.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Use \(CarnivalNumber.text(total)) g in Meal") { use(meal); dismiss() }
                    .font(.headline)
                    .accessibilityIdentifier("quick-food-use-carbs")
            } else if !items.isEmpty {
                Text("Some added foods do not have usable carbohydrate estimates. Review your plate.")
                    .font(.footnote).foregroundStyle(.orange)
                Button("Review plate") { tab = 2 }
            }
        }
    }

    private func adjustQuickFood(_ food: CarnivalFood, by delta: Double) {
        if let index = items.firstIndex(where: { $0.id == food.id }) {
            let updated = items[index].portions + delta
            if updated < 0.000001 { items.remove(at: index) }
            else { items[index].portions = min(100, (updated * 1000).rounded() / 1000) }
        } else if delta > 0 && items.count < 20 {
            items.append(.init(food: food, portions: delta))
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
                        tab = 2
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

private enum CarnivalQuickCategory: String, CaseIterable, Identifiable {
    case starches = "Starches"
    case vegetables = "Vegetables"
    case fruit = "Fruit"
    case protein = "Protein"
    case desserts = "Desserts"
    case extras = "Extras"

    var id: String { rawValue }

    var foodNames: [String] {
        switch self {
        case .starches:
            return ["White rice", "Basmati rice", "Brown rice", "Fried rice", "Macaroni and cheese",
                    "Mashed potatoes", "Roast potatoes", "French fries", "Plain pasta",
                    "Plain rice noodles", "Sweetcorn", "Oatmeal plain", "Bread roll", "Bread slice",
                    "Quinoa", "Couscous", "Hash brown patty", "Cheese grits"]
        case .vegetables:
            return ["Sweetcorn", "Carrots", "Beets", "Bell peppers", "Plain boiled broccoli",
                    "Green beans", "Green peas", "Cucumber", "Tomato", "Spinach",
                    "Mixed roasted vegetables", "Plain lettuce greens", "Sautéed mushrooms"]
        case .fruit:
            return ["Watermelon", "Cantaloupe", "Pineapple", "Strawberries", "Mixed fruit cup",
                    "Mixed melon", "Apple", "Banana"]
        case .protein:
            return ["Chicken grilled plain", "Roast chicken plain", "Grilled salmon plain",
                    "Grilled white fish", "Fried egg", "Scrambled eggs", "Hard boiled egg",
                    "Shrimp cooked plain", "Plain cooked beef", "Roast beef", "Tuna canned plain"]
        case .desserts:
            return ["Chocolate cake", "Cheesecake", "Brownie", "Cookie", "Vanilla ice cream",
                    "Chocolate ice cream", "Strawberry ice cream", "Apple pie", "Flan / custard",
                    "Bread pudding", "Tres leches cake", "Beignet"]
        case .extras:
            return ["2% milk", "Chocolate milk", "Plain yogurt", "Yogurt parfait", "Nuts",
                    "BBQ sauce", "Salsa", "Creamy salad dressing", "Peanut butter", "Honey",
                    "Syrup", "Orange juice", "Apple juice", "Corn tortilla small", "Croutons"]
        }
    }
}

private enum CarnivalQuickPortion {
    static func cupBase(for food: CarnivalFood) -> Double? {
        let parts = food.portion.split(separator: " ")
        guard parts.count > 1, parts[1].lowercased() == "cup" else { return nil }
        switch parts[0] {
        case "1/4": return 0.25
        case "1/3": return 1.0 / 3.0
        case "1/2": return 0.5
        case "1": return 1.0
        default: return nil
        }
    }

    static func step(for food: CarnivalFood) -> Double {
        if let cups = cupBase(for: food) { return 0.25 / cups }
        return 0.5 // Half of the catalog's explicit serving for pieces and non-cup foods.
    }

    static func stepLabel(for food: CarnivalFood) -> String {
        cupBase(for: food) != nil ? "¼ cup" : "½ listed serving (\(food.portion))"
    }

    static func amountLabel(for item: CarnivalMeal.Item) -> String {
        if let cups = cupBase(for: item.food) {
            return "\(CarnivalNumber.text(item.portions * cups)) cup"
        }
        return "\(CarnivalNumber.text(item.portions)) × \(item.food.portion)"
    }
}
