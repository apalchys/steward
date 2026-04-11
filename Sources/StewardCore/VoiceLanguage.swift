import Foundation

public enum VoiceLanguage: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case mandarinChinese = "zh"
    case spanish = "es"
    case english = "en"
    case arabic = "ar"
    case hindi = "hi"
    case portuguese = "pt"
    case bengali = "bn"
    case russian = "ru"
    case japanese = "ja"
    case punjabi = "pa"
    case vietnamese = "vi"
    case turkish = "tr"
    case marathi = "mr"
    case telugu = "te"
    case indonesian = "id"
    case korean = "ko"
    case french = "fr"
    case tamil = "ta"
    case german = "de"
    case urdu = "ur"
    case javanese = "jv"
    case italian = "it"
    case persian = "fa"
    case gujarati = "gu"
    case pashto = "ps"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .mandarinChinese:
            return "Mandarin Chinese"
        case .spanish:
            return "Spanish"
        case .english:
            return "English"
        case .arabic:
            return "Arabic"
        case .hindi:
            return "Hindi"
        case .portuguese:
            return "Portuguese"
        case .bengali:
            return "Bengali"
        case .russian:
            return "Russian"
        case .japanese:
            return "Japanese"
        case .punjabi:
            return "Punjabi"
        case .vietnamese:
            return "Vietnamese"
        case .turkish:
            return "Turkish"
        case .marathi:
            return "Marathi"
        case .telugu:
            return "Telugu"
        case .indonesian:
            return "Indonesian"
        case .korean:
            return "Korean"
        case .french:
            return "French"
        case .tamil:
            return "Tamil"
        case .german:
            return "German"
        case .urdu:
            return "Urdu"
        case .javanese:
            return "Javanese"
        case .italian:
            return "Italian"
        case .persian:
            return "Persian"
        case .gujarati:
            return "Gujarati"
        case .pashto:
            return "Pashto"
        }
    }
}
