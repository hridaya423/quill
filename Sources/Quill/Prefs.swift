import Foundation
import QuillCore

enum TalkKey: String, CaseIterable, Identifiable {
    case rightOption, rightCommand, fn

    var id: String { rawValue }

    var keyCode: UInt16 {
        switch self {
        case .rightOption: 61
        case .rightCommand: 54
        case .fn: 63
        }
    }

    var label: String {
        switch self {
        case .rightOption: "right ⌥"
        case .rightCommand: "right ⌘"
        case .fn: "fn"
        }
    }

    var word: String {
        switch self {
        case .rightOption: "right Option"
        case .rightCommand: "right Command"
        case .fn: "fn"
        }
    }

    var title: String {
        switch self {
        case .rightOption: "Right Option (⌥)"
        case .rightCommand: "Right Command (⌘)"
        case .fn: "Fn (🌐)"
        }
    }
}

enum Prefs {
    nonisolated(unsafe) static let store = ProcessInfo.processInfo.environment["QUILL_DEFAULTS"].flatMap { UserDefaults(suiteName: $0) } ?? .standard

    static var vault: String? {
        get { store.string(forKey: "vault") }
        set { store.set(newValue, forKey: "vault") }
    }

    static var last: String? {
        get { store.string(forKey: "last") }
        set { store.set(newValue, forKey: "last") }
    }

    static var mode: Mode {
        get { Mode(rawValue: store.string(forKey: "mode") ?? "") ?? .guided }
        set { store.set(newValue.rawValue, forKey: "mode") }
    }

    static var agent: String {
        get { store.string(forKey: "agent") ?? "claude" }
        set { store.set(newValue, forKey: "agent") }
    }

    static var endpoint: String {
        get {
            var url = (store.string(forKey: "endpoint") ?? ProcessInfo.processInfo.environment["QUILL_API_URL"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            while url.hasSuffix("/") { url.removeLast() }
            if let parsed = URL(string: url), parsed.host != nil, parsed.path.isEmpty { url += "/v1" }
            return url
        }
        set { store.set(newValue, forKey: "endpoint") }
    }

    static var expanded: [String] {
        get { store.stringArray(forKey: "expanded") ?? [] }
        set { store.set(newValue, forKey: "expanded") }
    }

    static func model(_ agent: String) -> String? { store.string(forKey: "model." + agent) }
    static func setModel(_ value: String, for agent: String) { store.set(value, forKey: "model." + agent) }

    static var onboarded: Bool {
        get { store.bool(forKey: "onboarded") }
        set { store.set(newValue, forKey: "onboarded") }
    }

    static var onboardStarted: Double {
        get { store.double(forKey: "onboardStarted") }
        set { store.set(newValue, forKey: "onboardStarted") }
    }

    static var spoke: Bool {
        get { store.bool(forKey: "spoke") }
        set { store.set(newValue, forKey: "spoke") }
    }

    static var history: [String] {
        get { store.stringArray(forKey: "history") ?? [] }
        set { store.set(newValue, forKey: "history") }
    }

    static var zoom: Double {
        get { store.double(forKey: "zoom") }
        set { store.set(newValue, forKey: "zoom") }
    }

    static var measuredAt: Double {
        get { store.double(forKey: "measuredAt") }
        set { store.set(newValue, forKey: "measuredAt") }
    }

    static var ownTells: Set<String> {
        get { Set(store.stringArray(forKey: "ownTells") ?? []) }
        set { store.set(newValue.sorted(), forKey: "ownTells") }
    }

    static var voiceSources: [String] {
        get { store.stringArray(forKey: "voiceSources") ?? [] }
        set { store.set(newValue, forKey: "voiceSources") }
    }

    static var distilledThrough: Int {
        get { store.integer(forKey: "distilledThrough") }
        set { store.set(newValue, forKey: "distilledThrough") }
    }

    static var pane: String? {
        get { store.string(forKey: "settingsPane") }
        set { store.set(newValue, forKey: "settingsPane") }
    }

    static var talkKey: TalkKey {
        get { TalkKey(rawValue: store.string(forKey: "talkKey") ?? "") ?? .rightOption }
        set { store.set(newValue.rawValue, forKey: "talkKey") }
    }
}
