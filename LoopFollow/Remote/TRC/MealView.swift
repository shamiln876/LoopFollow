// LoopFollow
// MealView.swift

import HealthKit
import LocalAuthentication
import SwiftUI

struct MealView: View {
    @Environment(\.presentationMode) private var presentationMode
    @State private var showMealReview = false
    @State private var advisorDraft: SmartMealDraft?
    @State private var advisorAttempted = false
    @ObservedObject private var liveMealSnapshot = Observable.shared.mealReview
    @State private var advisorReceipt = SmartMealSendJournal.shared.lastReceipt(source: Storage.shared.url.value)
    @State private var isAuthenticating = false
    @State private var advisorUnresolved = SmartMealSendJournal.shared.hasPending(source: Storage.shared.url.value)
    @State private var carbs = HKQuantity(unit: .gram(), doubleValue: 0.0)
    @State private var protein = HKQuantity(unit: .gram(), doubleValue: 0.0)
    @State private var fat = HKQuantity(unit: .gram(), doubleValue: 0.0)
    @State private var bolusAmount = HKQuantity(unit: .internationalUnit(), doubleValue: 0.0)

    private let pushNotificationManager = PushNotificationManager()

    @ObservedObject private var maxCarbs = Storage.shared.maxCarbs
    @ObservedObject private var maxProtein = Storage.shared.maxProtein
    @ObservedObject private var maxFat = Storage.shared.maxFat
    @ObservedObject private var mealWithBolus = Storage.shared.mealWithBolus
    @ObservedObject private var mealWithFatProtein = Storage.shared.mealWithFatProtein
    @ObservedObject private var maxBolus = Storage.shared.maxBolus
    @ObservedObject private var quickPickMeals = QuickPickMealsManager.shared

    @FocusState private var carbsFieldIsFocused: Bool
    @FocusState private var proteinFieldIsFocused: Bool
    @FocusState private var fatFieldIsFocused: Bool
    @FocusState private var bolusFieldIsFocused: Bool

    @State private var showAlert: Bool = false
    @State private var alertType: AlertType? = nil
    @State private var alertMessage: String? = nil
    @State private var isLoading: Bool = false
    @State private var statusMessage: String? = nil
    @State private var selectedTime: Date? = nil
    @State private var isScheduling: Bool = false
    @State private var showFatProteinOrderBanner = false

    init(initialAdvisorDraft: SmartMealDraft? = nil, initialCarbs: Double = 0) {
        _advisorDraft = State(initialValue: initialAdvisorDraft)
        if let draft = initialAdvisorDraft {
            _carbs = State(initialValue: HKQuantity(unit: .gram(), doubleValue: Double(draft.plan.immediateCarbs)))
            _protein = State(initialValue: HKQuantity(unit: .gram(), doubleValue: draft.protein))
            _fat = State(initialValue: HKQuantity(unit: .gram(), doubleValue: draft.fat))
            _bolusAmount = State(initialValue: HKQuantity(unit: .internationalUnit(), doubleValue: draft.plan.upfrontInsulin))
        } else if initialCarbs.isFinite, initialCarbs >= 0 {
            _carbs = State(initialValue: HKQuantity(unit: .gram(), doubleValue: initialCarbs))
        }
    }

    enum AlertType {
        case confirmMeal
        case statusSuccess
        case statusFailure
        case validationError
    }

    var body: some View {
        NavigationView {
            VStack {
                Form {
                    Section {
                        Button("Smart Meal Advisor") { showMealReview = true }
                            .accessibilityIdentifier("meal-open-advisor")
                    }
                    if advisorUnresolved {
                        Section("Previous advisor send needs checking") {
                            if SmartMealSendJournal.shared.pendingRequest(source: Storage.shared.url.value) != nil {
                                Text("Waiting for Trio's transaction receipt. Check actual carb entries and insulin in Trio/Nightscout. For an uncertain receiver result, acknowledge the check in Trio → Settings → Remote Control. Do not repeat this meal.")
                                Button("I checked treatments · clear expired sender attempt") {
                                    if SmartMealSendJournal.shared.reconcile(source: Storage.shared.url.value) { advisorUnresolved = false }
                                }
                                Text("Available only after this command expires. Trio still blocks a new meal until any uncertain receiver transaction is checked.").font(.footnote)
                            } else {
                                Text("Check Trio and Nightscout for the actual meal and insulin before another advisor send. APNs acceptance does not confirm delivery.")
                                Button("I checked Trio/Nightscout · allow a new review") {
                                    if SmartMealSendJournal.shared.reconcile(source: Storage.shared.url.value) { advisorUnresolved = false }
                                }
                            }
                        }
                    }
                    if let receipt = advisorReceipt {
                        Section("Trio meal result") {
                            Text(receipt.message)
                            Text("Carbs: \(receipt.request.immediateCarbs) g now · \(receipt.request.delayedCarbs) g later. No later insulin bolus.").font(.footnote)
                        }
                    }
                    if let draft = advisorDraft {
                        Section("Smart Meal Advisor draft") {
                            Text("Carbs now: \(draft.plan.immediateCarbs) g · later: \(draft.plan.delayedCarbs) g. Selected insulin: \(InsulinFormatter.shared.string(bolusAmount.doubleValue(for: .internationalUnit()))) U")
                            if draft.plan.delayedCarbs > 0 {
                                Text("Later carbs: +\(Int(draft.plan.delayMinutes)) minutes. Insulin later: none.")
                                if !batchAvailable { Text(RiceMealPlan.sendingBlocker).foregroundStyle(.orange) }
                            }
                            Text("Draft expires after two minutes or a new Trio snapshot. Review again if held.").font(.footnote)
                            Button("Discard advisor draft") {
                                advisorDraft = nil
                                carbs = HKQuantity(unit: .gram(), doubleValue: 0)
                                protein = HKQuantity(unit: .gram(), doubleValue: 0)
                                fat = HKQuantity(unit: .gram(), doubleValue: 0)
                                bolusAmount = HKQuantity(unit: .internationalUnit(), doubleValue: 0)
                            }
                        }
                    }
                    if !quickPickMeals.quickPickMeals.isEmpty {
                        Section(header: QuickPickSectionHeader(title: "Quick-Pick Meals", infoText: QuickPickSectionHeader.mealInfoText)) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(quickPickMeals.quickPickMeals) { meal in
                                        Button {
                                            applyQuickPickMeal(meal)
                                        } label: {
                                            VStack(spacing: 2) {
                                                Text("\(Int(meal.carbs))g")
                                                    .font(.subheadline.weight(.medium))
                                                if mealWithFatProtein.value, meal.fat > 0 || meal.protein > 0 {
                                                    Text("F\(Int(meal.fat)) P\(Int(meal.protein))")
                                                        .font(.caption2)
                                                }
                                                if mealWithBolus.value, meal.bolus > 0 {
                                                    Text("\(InsulinFormatter.shared.string(meal.bolus))U")
                                                        .font(.caption2)
                                                }
                                            }
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 8)
                                            .background(Color.accentColor.opacity(0.15))
                                            .foregroundColor(.accentColor)
                                            .cornerRadius(8)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }

                    Section(header: Text("Meal Data")) {
                        // TODO: This banner can be deleted in March 2027. Check the commit for other places to cleanup.
                        if showFatProteinOrderBanner {
                            HStack {
                                Image(systemName: "arrow.left.arrow.right")
                                Text("The order of Fat and Protein inputs has changed.").font(.callout)
                                Spacer()
                                Button {
                                    Storage.shared.hasSeenFatProteinOrderChange.value = true
                                    withAnimation { showFatProteinOrderBanner = false }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                }
                                .buttonStyle(.plain)
                            }
                            .listRowBackground(Color.orange.opacity(0.75))
                            .transition(.opacity)
                        }

                        HKQuantityInputView(
                            label: "Carbs",
                            quantity: $carbs,
                            unit: .gram(),
                            maxLength: 4,
                            minValue: HKQuantity(unit: .gram(), doubleValue: 0),
                            maxValue: maxCarbs.value,
                            isFocused: $carbsFieldIsFocused,
                            onValidationError: { message in
                                handleValidationError(message)
                            }
                        )

                        if mealWithFatProtein.value || advisorDraft != nil {
                            HKQuantityInputView(
                                label: "Fat",
                                quantity: $fat,
                                unit: .gram(),
                                maxLength: 4,
                                minValue: HKQuantity(unit: .gram(), doubleValue: 0),
                                maxValue: maxFat.value,
                                isFocused: $fatFieldIsFocused,
                                onValidationError: { message in
                                    handleValidationError(message)
                                }
                            )

                            HKQuantityInputView(
                                label: "Protein",
                                quantity: $protein,
                                unit: .gram(),
                                maxLength: 4,
                                minValue: HKQuantity(unit: .gram(), doubleValue: 0),
                                maxValue: maxProtein.value,
                                isFocused: $proteinFieldIsFocused,
                                onValidationError: { message in
                                    handleValidationError(message)
                                }
                            )
                        }

                        if mealWithBolus.value || advisorDraft != nil {
                            HKQuantityInputView(
                                label: "Bolus Amount",
                                quantity: $bolusAmount,
                                unit: .internationalUnit(),
                                maxLength: 4,
                                minValue: HKQuantity(unit: .internationalUnit(), doubleValue: 0),
                                maxValue: maxBolus.value,
                                isFocused: $bolusFieldIsFocused,
                                onValidationError: { message in
                                    handleValidationError(message)
                                }
                            )
                        }
                    }

                    Section(header: Text("Schedule")) {
                        Toggle("Schedule for later", isOn: $isScheduling).disabled(advisorDraft != nil)
                        if isScheduling {
                            DatePicker(
                                "Select Time",
                                selection: Binding(
                                    get: { self.selectedTime ?? Date() },
                                    set: { self.selectedTime = $0 }
                                ),
                                displayedComponents: .hourAndMinute
                            )
                            .datePickerStyle(CompactDatePickerStyle())

                            if bolusAmount.doubleValue(for: .internationalUnit()) > 0 {
                                Text("Note: The meal will be scheduled, but the bolus is enacted immediately.")
                            }
                        }
                    }
                }
                .disabled(isLoading || isAuthenticating)
                .safeAreaInset(edge: .bottom) {
                    Button {
                        carbsFieldIsFocused = false
                        proteinFieldIsFocused = false
                        fatFieldIsFocused = false

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            guard carbs.doubleValue(for: .gram()) != 0 ||
                                protein.doubleValue(for: .gram()) != 0 ||
                                fat.doubleValue(for: .gram()) != 0
                            else {
                                return
                            }
                            if !showAlert {
                                alertType = .confirmMeal
                                showAlert = true
                            }
                        }
                    } label: {
                        if isLoading {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Sending Meal Data...")
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            Text("Send Meal")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isButtonDisabled)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(.bar)
                }
                .navigationTitle("Meal")
                .navigationBarTitleDisplayMode(.inline)
            }
            .sheet(isPresented: $showMealReview) {
                MealReviewView(initialCarbs: advisorDraft.map { Double($0.plan.immediateCarbs + $0.plan.delayedCarbs) } ?? carbs.doubleValue(for: .gram()), initialBolus: advisorDraft.flatMap { draft in
                    let current = bolusAmount.doubleValue(for: .internationalUnit())
                    return draft.plan.usesManualBolus || current != draft.plan.upfrontInsulin ? current : nil
                }, initialPlan: advisorDraft?.plan, onManualMeal: { amount in
                    advisorDraft = nil
                    carbs = HKQuantity(unit: .gram(), doubleValue: amount)
                    protein = HKQuantity(unit: .gram(), doubleValue: 0)
                    fat = HKQuantity(unit: .gram(), doubleValue: 0)
                    bolusAmount = HKQuantity(unit: .internationalUnit(), doubleValue: 0)
                    isScheduling = false
                    selectedTime = nil
                }, onUse: { draft in
                    advisorDraft = draft
                    advisorAttempted = false
                    carbs = HKQuantity(unit: .gram(), doubleValue: Double(draft.plan.immediateCarbs))
                    protein = HKQuantity(unit: .gram(), doubleValue: draft.protein)
                    fat = HKQuantity(unit: .gram(), doubleValue: draft.fat)
                    bolusAmount = HKQuantity(unit: .internationalUnit(), doubleValue: draft.plan.upfrontInsulin)
                    isScheduling = false
                    selectedTime = nil
                })
            }
            .onChange(of: liveMealSnapshot.value) { _, _ in
                advisorUnresolved = SmartMealSendJournal.shared.hasPending(source: Storage.shared.url.value)
                advisorReceipt = SmartMealSendJournal.shared.lastReceipt(source: Storage.shared.url.value)
            }
            .onAppear {
                selectedTime = nil
                isScheduling = false

                quickPickMeals.refresh(
                    maxCarbs: maxCarbs.value.doubleValue(for: .gram()),
                    includeFatProtein: mealWithFatProtein.value
                )

                if !Storage.shared.hasSeenFatProteinOrderChange.value && Storage.shared.mealWithFatProtein.value {
                    showFatProteinOrderBanner = true
                }
            }
            .alert(isPresented: $showAlert) {
                switch alertType {
                case .confirmMeal:
                    let carbsAmount = carbs.doubleValue(for: HKUnit.gram())
                    let proteinAmount = protein.doubleValue(for: HKUnit.gram())
                    let fatAmount = fat.doubleValue(for: HKUnit.gram())
                    let bolusAmount = bolusAmount.doubleValue(for: .internationalUnit())

                    var message = "Are you sure you want to send the meal data"

                    if let selectedTime = selectedTime {
                        let timeFormatter = DateFormatter()
                        timeFormatter.timeStyle = .short
                        let timeString = timeFormatter.string(from: selectedTime)
                        message += " for \(timeString)?"
                    } else {
                        message += " now?"
                    }

                    if carbsAmount > 0 {
                        message += String(format: "\nCarbs: %.0f g", carbsAmount)
                    }

                    if let draft = advisorDraft, draft.plan.delayedCarbs > 0 {
                        message += "\nLater carbs: \(draft.plan.delayedCarbs) g at +\(Int(draft.plan.delayMinutes)) min"
                        message += "\nNo later insulin bolus."
                    }
                    if proteinAmount > 0 {
                        message += String(format: "\nProtein: %.0f g", proteinAmount)
                    }

                    if fatAmount > 0 {
                        message += String(format: "\nFat: %.0f g", fatAmount)
                    }

                    if bolusAmount > 0 {
                        message += String(format: "\nBolus: %.2f U", bolusAmount)
                    }

                    return Alert(
                        title: Text("Confirm Meal"),
                        message: Text(message),
                        primaryButton: .default(Text("Confirm"), action: {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                if bolusAmount > 0 {
                                    isAuthenticating = true
                                    AuthService.authenticate(reason: "Confirm your identity to send bolus.") { result in
                                        DispatchQueue.main.async {
                                            isAuthenticating = false
                                            switch result {
                                            case .success:
                                                self.sendMealCommand()
                                            case let .unavailable(message):
                                                self.alertMessage = message
                                                self.alertType = .validationError
                                                self.showAlert = true
                                            case .failed:
                                                self.alertMessage = "Authentication failed"
                                                self.alertType = .validationError
                                                self.showAlert = true
                                            case .canceled:
                                                // User canceled, no alert
                                                break
                                            }
                                        }
                                    }
                                } else {
                                    self.sendMealCommand()
                                }
                            }
                        }),
                        secondaryButton: .cancel()
                    )
                case .statusSuccess:
                    return Alert(
                        title: Text("Command Sent"),
                        message: Text(statusMessage ?? ""),
                        dismissButton: .default(Text("OK"), action: {
                            presentationMode.wrappedValue.dismiss()
                        })
                    )
                case .statusFailure:
                    return Alert(
                        title: Text("Status"),
                        message: Text(statusMessage ?? ""),
                        dismissButton: .default(Text("OK"))
                    )
                case .validationError:
                    return Alert(
                        title: Text("Validation Error"),
                        message: Text(alertMessage ?? ""),
                        dismissButton: .default(Text("OK"))
                    )
                case .none:
                    return Alert(title: Text("Unknown Alert"))
                }
            }
        }
    }

    private var batchAvailable: Bool {
        SmartMealDelivery.available(snapshot: liveMealSnapshot.value, settings: Storage.shared.mealReviewSettings.value,
                                    bundleID: Storage.shared.bundleId.value, now: Date())
    }

    private var isButtonDisabled: Bool {
        let requiresReceiver = advisorDraft.map { $0.plan.delayedCarbs > 0 || $0.settings.receiverConfigurationID != nil } ?? false
        return isLoading || isAuthenticating || (requiresReceiver && !batchAvailable)
            || advisorAttempted || (advisorDraft != nil && advisorUnresolved)
    }

    private func sendMealCommand() {
        guard !isLoading else { return }
        var smartRequest: SmartMealRequest?
        if let draft = advisorDraft {
            let current = Date()
            // A receiver-backed draft must never downgrade to the legacy command.
            guard !advisorAttempted,
                  (draft.plan.delayedCarbs == 0 && draft.settings.receiverConfigurationID == nil) || batchAvailable, !isScheduling,
                  draft.isCurrent(now: current, settings: Storage.shared.mealReviewSettings.value,
                                  snapshot: Observable.shared.mealReview.value, source: Storage.shared.url.value),
                  MealReviewCalculation.reasons(snapshot: Observable.shared.mealReview.value,
                                                samples: Observable.shared.mealReviewGlucose.value,
                                                newestTreatment: Observable.shared.mealReviewNewestTreatment.value, now: current,
                                                allowLowPredictionReview: draft.lowPredictionAcknowledged && Observable.shared.mealReview.value?.smartMeal?.allowsLowPredictionReview == true).isEmpty,
                  carbs.doubleValue(for: .gram()) == Double(draft.plan.immediateCarbs),
                  bolusAmount.doubleValue(for: .internationalUnit()) <= maxBolus.value.doubleValue(for: .internationalUnit()),
                  bolusAmount.doubleValue(for: .internationalUnit()) >= 0,
                  (0 ... 600).contains(where: { Double($0) / 20 == bolusAmount.doubleValue(for: .internationalUnit()) }),
                  protein.doubleValue(for: .gram()) >= 0,
                  fat.doubleValue(for: .gram()) >= 0,
                  protein.doubleValue(for: .gram()) <= maxProtein.value.doubleValue(for: .gram()),
                  fat.doubleValue(for: .gram()) <= maxFat.value.doubleValue(for: .gram()),
                  carbs.doubleValue(for: .gram()) <= maxCarbs.value.doubleValue(for: .gram())
            else {
                alertMessage = "Advisor draft held. Changed carbs, stale inputs/settings or missing Trio capability require a fresh review. Nothing sent."
                alertType = .validationError
                showAlert = true
                return
            }
            if batchAvailable {
                smartRequest = SmartMealDelivery.request(draft: draft, bolus: bolusAmount.doubleValue(for: .internationalUnit()),
                                                         protein: protein.doubleValue(for: .gram()), fat: fat.doubleValue(for: .gram()),
                                                         snapshot: liveMealSnapshot.value, settings: Storage.shared.mealReviewSettings.value,
                                                         bundleID: Storage.shared.bundleId.value, now: current)
                guard smartRequest != nil else {
                    alertMessage = "Smart meal held: invalid meal values or changed receiver settings. Review again. Nothing sent."
                    alertType = .validationError; showAlert = true; return
                }
            }
            // Persist before transport. Neither timeout nor APNs acceptance permits a blind retry.
            let claimed = smartRequest.map { SmartMealSendJournal.shared.claim(request: $0, source: draft.source) }
                ?? SmartMealSendJournal.shared.claim(source: draft.source)
            guard claimed else {
                advisorUnresolved = true
                alertMessage = "Advisor send held: an earlier attempt needs checking, or its pending record could not be saved. Nothing sent."
                alertType = .validationError
                showAlert = true
                return
            }
            advisorUnresolved = true
            advisorAttempted = true
        }
        isLoading = true

        var scheduledDate: Date? = nil
        if isScheduling, let selectedTime = selectedTime {
            let calendar = Calendar.current
            let now = Date()
            let selectedDateComponents = calendar.dateComponents([.hour, .minute], from: selectedTime)
            let currentSecond = calendar.component(.second, from: now)
            scheduledDate = calendar.date(bySettingHour: selectedDateComponents.hour ?? 0,
                                          minute: selectedDateComponents.minute ?? 0,
                                          second: currentSecond,
                                          of: now) ?? now
        }

        let isSmartMeal = smartRequest != nil
        let completion: (Bool, String?) -> Void = { success, errorMessage in
            DispatchQueue.main.async {
                isLoading = false
                if success {
                    let sentCarbs = carbs.doubleValue(for: .gram())
                    if sentCarbs > 0 && !isSmartMeal {
                        QuickPickMealsManager.shared.recordMeal(
                            carbs: sentCarbs,
                            fat: fat.doubleValue(for: .gram()),
                            protein: protein.doubleValue(for: .gram()),
                            bolus: bolusAmount.doubleValue(for: .internationalUnit())
                        )
                    }
                    statusMessage = isSmartMeal
                        ? "Request sent. Waiting for Trio to confirm meal entries and upfront bolus initiation. Nothing is confirmed by APNs acceptance alone."
                        : RemoteCommandMessage.sent
                    LogManager.shared.log(
                        category: .apns,
                        message: "sendMealPushNotification succeeded - Carbs: \(carbs.doubleValue(for: .gram())) g, Protein: \(protein.doubleValue(for: .gram())) g, Fat: \(fat.doubleValue(for: .gram())) g, Bolus: \(bolusAmount.doubleValue(for: .internationalUnit())) U, Scheduled: \(scheduledDate != nil ? formatDate(scheduledDate!) : "now")"
                    )

                    // Reset meal values and scheduled data after success
                    carbs = HKQuantity(unit: .gram(), doubleValue: 0.0)
                    protein = HKQuantity(unit: .gram(), doubleValue: 0.0)
                    fat = HKQuantity(unit: .gram(), doubleValue: 0.0)
                    selectedTime = nil
                    isScheduling = false
                    alertType = .statusSuccess
                } else {
                    statusMessage = (errorMessage ?? "Failed to send meal command.") + (advisorDraft != nil ? " Delivery is uncertain. Check Trio and Nightscout before creating another draft; do not retry blindly." : "")
                    LogManager.shared.log(
                        category: .apns,
                        message: "sendMealPushNotification failed with error: \(errorMessage ?? "unknown error")"
                    )
                    alertType = .statusFailure
                }
                showAlert = true
            }
        }
        if let smartRequest {
            pushNotificationManager.sendSmartMealPushNotification(request: smartRequest, completion: completion)
        } else {
            pushNotificationManager.sendMealPushNotification(carbs: carbs, protein: protein, fat: fat,
                                                             bolusAmount: bolusAmount, scheduledTime: scheduledDate, completion: completion)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func applyQuickPickMeal(_ meal: QuickPickMeal) {
        let maxC = maxCarbs.value.doubleValue(for: .gram())
        carbs = HKQuantity(unit: .gram(), doubleValue: min(meal.carbs, maxC))
        if mealWithFatProtein.value {
            let maxF = maxFat.value.doubleValue(for: .gram())
            let maxP = maxProtein.value.doubleValue(for: .gram())
            fat = HKQuantity(unit: .gram(), doubleValue: min(meal.fat, maxF))
            protein = HKQuantity(unit: .gram(), doubleValue: min(meal.protein, maxP))
        }
        if mealWithBolus.value, meal.bolus > 0 {
            let maxB = maxBolus.value.doubleValue(for: .internationalUnit())
            bolusAmount = HKQuantity(unit: .internationalUnit(), doubleValue: min(meal.bolus, maxB))
        }
    }

    private func handleValidationError(_ message: String) {
        alertMessage = message
        alertType = .validationError
        showAlert = true
    }
}
