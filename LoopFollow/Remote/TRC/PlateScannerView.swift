// LoopFollow
// PlateScannerView.swift

import PhotosUI
import SwiftUI
import UIKit

struct PlateScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("plateScannerEndpoint") private var endpoint = ""
    @State private var token = PlateScanCredentials.read()
    @State private var photo: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var camera = false
    @State private var items: [PlateScanItem] = []
    @State private var busy = false
    @State private var error: String?
    @State private var task: Task<Void, Never>?
    @State private var showSetup = false
    let catalog: CarnivalFoodCatalog
    let accept: (CarnivalMeal) -> Void

    init(catalog: CarnivalFoodCatalog, initialItems: [PlateScanItem] = [], accept: @escaping (CarnivalMeal) -> Void) {
        self.catalog = catalog
        self.accept = accept
        #if DEBUG && targetEnvironment(simulator)
            if ProcessInfo.processInfo.arguments.contains("--plate-scanner-ui-test"),
               let food = catalog.foods.first(where: { $0.id == "MG8D7CE49" })
            {
                _items = State(initialValue: [
                    .init(label: "Plain bagel", food: food, portions: 0.5, uncertainty: "Synthetic suggestion; verify portion", confirmed: false),
                    .init(label: "Unknown sauce", food: nil, portions: 1, uncertainty: "Cannot identify", confirmed: false),
                ])
            } else { _items = State(initialValue: initialItems) }
        #else
            _items = State(initialValue: initialItems)
        #endif
    }

    private var ready: Bool { PlateScanClient.endpoint(endpoint) != nil && !token.isEmpty }
    private var meal: CarnivalMeal? { PlateScanReview.meal(items, catalog: catalog) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Optional photo scanner") {
                    Text("Only a photo you take or select here is sent to your configured AI service. Review every food and portion; sauces and hidden ingredients can be missed. No glucose or insulin data are sent.")
                        .font(.footnote)
                    PhotosPicker(selection: $photo, matching: .images) { Label("Upload photo", systemImage: "photo") }
                        .disabled(busy || !ready).accessibilityIdentifier("plate-upload")
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button { camera = true } label: { Label("Take photo", systemImage: "camera") }.disabled(busy || !ready)
                    }
                    if !ready { Text("Live photo analysis is not configured. Close this screen to use the offline manual guide.").foregroundStyle(.secondary) }
                    Button("Scanner setup") { showSetup.toggle() }.disabled(busy)
                    if showSetup {
                        TextField("HTTPS scanner URL", text: $endpoint).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        SecureField("Scanner access token", text: $token).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button("Save setup") {
                            if PlateScanCredentials.save(token) { showSetup = false }
                            else { error = "Could not save the scanner token securely." }
                        }
                        Text("Use a private service token here. The OpenAI API key belongs only in the server's secret store.").font(.footnote)
                    }
                    if let image { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 180).accessibilityLabel("Selected plate photo") }
                    if busy { ProgressView("Identifying foods and visible portions…") }
                    if let error { Text(error).foregroundStyle(.orange) }
                }
                if !items.isEmpty {
                    Section("Review each food") {
                        ForEach(items) { snapshot in
                            PlateScanFoodRow(item: binding(for: snapshot), catalog: catalog) {
                                items.removeAll { $0.id == snapshot.id }
                            }
                        }
                        NavigationLink("Add food") {
                            PlateScanMatchView(catalog: catalog) { food in
                                items.append(.init(label: food.name, food: food, portions: 1, uncertainty: "Manually added; set portion.", confirmed: false, portionNeedsEntry: true))
                            }
                        }.disabled(items.count >= 20 || busy)
                    }
                    Section("Estimated total carbs") {
                        let subtotal = items.filter { !$0.portionNeedsEntry && $0.food?.available == true }.reduce(0.0) { $0 + ($1.food?.carbs ?? 0) * $1.portions }
                        Text("\(meal == nil ? "Known-food subtotal: " : "")\(CarnivalNumber.text(subtotal)) g\(meal == nil ? " · total incomplete / awaiting review" : "")").font(.title3).monospacedDigit().accessibilityIdentifier("plate-scan-total")
                        Text("Unknown foods are not zero carbs. Match or explicitly remove every unresolved item, confirm portions, and add anything the photo missed. Removing an item excludes it from the total.").font(.footnote)
                        Button("Accept — fill Smart Meal Advisor") { if let meal { accept(meal); dismiss() } }
                            .disabled(meal == nil || busy).accessibilityIdentifier("plate-scan-accept")
                    }
                }
            }
            .navigationTitle("Review plate photo").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .sheet(isPresented: $camera) { PlateCamera { selected in camera = false; if let selected { analyze(selected) } } }
        .onChange(of: photo) { _, selection in
            guard let selection else { return }
            task?.cancel()
            task = Task { @MainActor in
                do {
                    guard let data = try await selection.loadTransferable(type: Data.self), data.count <= 30_000_000,
                          let selected = UIImage(data: data) else { throw PlateScanError.invalidResponse }
                    guard !Task.isCancelled else { return }; analyze(selected)
                } catch { self.error = "Could not open that photo. Try a smaller image." }
            }
        }
        .onDisappear { task?.cancel() }
    }

    /// Deleted rows may remain alive during Form animations/accessibility queries.
    /// Resolve by stable ID, never retain an array-index Binding after removal.
    private func binding(for snapshot: PlateScanItem) -> Binding<PlateScanItem> {
        Binding(get: { items.first { $0.id == snapshot.id } ?? snapshot }, set: { updated in
            if let index = items.firstIndex(where: { $0.id == snapshot.id }) { items[index] = updated }
        })
    }

    @MainActor private func analyze(_ selected: UIImage) {
        task?.cancel(); items = []; error = nil; busy = true
        // Redraw at a bounded size: strips EXIF/GPS metadata and normalizes orientation.
        let scale = min(1, 1280 / max(selected.size.width, selected.size.height))
        let size = CGSize(width: max(1, selected.size.width * scale), height: max(1, selected.size.height * scale))
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let normalized = UIGraphicsImageRenderer(size: size, format: format).image { _ in selected.draw(in: CGRect(origin: .zero, size: size)) }
        image = normalized
        guard let jpeg = normalized.jpegData(compressionQuality: 0.8) else { busy = false; error = "Could not prepare that image."; return }
        task = Task { @MainActor in
            defer { busy = false }
            do {
                let result = try await PlateScanClient.scan(jpeg: jpeg, endpoint: endpoint, token: token, catalog: catalog)
                guard !Task.isCancelled else { return }; items = result
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
}

private struct PlateScanFoodRow: View {
    @Binding var item: PlateScanItem
    let catalog: CarnivalFoodCatalog
    let remove: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.label).font(.headline)
            if !item.uncertainty.isEmpty { Text(item.uncertainty).font(.footnote).foregroundStyle(.orange) }
            NavigationLink {
                PlateScanMatchView(catalog: catalog) { food in
                    item.food = food; item.portions = 1; item.confirmed = false; item.portionNeedsEntry = true
                }
            } label: {
                Text(item.food.map { "\($0.name) · \($0.venue)" } ?? "Unknown food — choose a catalog match")
            }.buttonStyle(.borderless)
            if let food = item.food {
                Text("Base portion: \(food.portion)").font(.footnote)
                HStack {
                    Text("\(CarnivalNumber.text(item.portions)) × base portion")
                    Spacer()
                    Button { item.portions = max(0.25, item.portions - 0.25); item.portionNeedsEntry = false; item.confirmed = false } label: { Image(systemName: "minus") }
                        .buttonStyle(.bordered).accessibilityLabel("Decrease portion").disabled(item.portions <= 0.25)
                    Button { item.portions = min(100, item.portions + 0.25); item.portionNeedsEntry = false; item.confirmed = false } label: { Image(systemName: "plus") }
                        .buttonStyle(.bordered).accessibilityLabel("Increase portion").disabled(item.portions >= 100)
                }
                if item.portionNeedsEntry {
                    Text("Carbs unavailable until you set the portion").foregroundStyle(.orange)
                } else if let carbs = food.carbs {
                    Text("Estimated carbs: \(CarnivalNumber.text(carbs * item.portions)) g").monospacedDigit()
                } else { Text("Nutrition unavailable — total incomplete").foregroundStyle(.orange) }
                if item.portionNeedsEntry {
                    Text("Photo could not establish an amount. Set your portion using − / +, or explicitly choose one base portion below.").foregroundStyle(.orange).font(.footnote)
                    Button("Use one listed base portion") { item.portions = 1; item.portionNeedsEntry = false; item.confirmed = false }.buttonStyle(.borderless)
                }
                Toggle("I checked this match and portion", isOn: $item.confirmed).disabled(!food.available || item.portionNeedsEntry)
            }
            Button("Remove food", role: .destructive, action: remove).buttonStyle(.borderless)
        }.padding(.vertical, 4)
    }
}

private struct PlateScanMatchView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    let catalog: CarnivalFoodCatalog
    let select: (CarnivalFood) -> Void
    var body: some View {
        List {
            TextField("Search food or venue", text: $query).autocorrectionDisabled().accessibilityIdentifier("plate-match-query")
            ForEach(Array(catalog.search(query).prefix(100))) { food in
                Button { select(food); dismiss() } label: {
                    VStack(alignment: .leading) {
                        Text(food.name); Text("\(food.venue) · \(food.portion)").font(.caption)
                        if !food.available { Text("Nutrition unavailable").foregroundStyle(.orange) }
                    }
                }.accessibilityIdentifier("plate-match-\(food.id)")
            }
            Text("No suitable catalog match? Leave the item unresolved and use manual carb entry instead.").font(.footnote)
        }.navigationTitle("Match Carnival food")
    }
}

private struct PlateCamera: UIViewControllerRepresentable {
    let complete: (UIImage?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(complete) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController(); picker.sourceType = .camera; picker.delegate = context.coordinator; return picker
    }

    func updateUIViewController(_: UIImagePickerController, context _: Context) {}
    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let complete: (UIImage?) -> Void
        init(_ complete: @escaping (UIImage?) -> Void) { self.complete = complete }
        func imagePickerControllerDidCancel(_: UIImagePickerController) { complete(nil) }
        func imagePickerController(_: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) { complete(info[.originalImage] as? UIImage) }
    }
}
