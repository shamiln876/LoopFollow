// LoopFollow
// TRCCommandType.swift

import Foundation

enum TRCCommandType: String, Encodable {
    case bolus
    case tempTarget = "temp_target"
    case cancelTempTarget = "cancel_temp_target"
    case meal
    case smartMeal = "smart_meal"
    case startOverride = "start_override"
    case cancelOverride = "cancel_override"

    var displayName: String {
        switch self {
        case .bolus: return "Bolus"
        case .tempTarget: return "Temp Target"
        case .cancelTempTarget: return "Cancel Temp Target"
        case .meal: return "Meal"
        case .smartMeal: return "Smart Meal"
        case .startOverride: return "Start Override"
        case .cancelOverride: return "Cancel Override"
        }
    }
}
