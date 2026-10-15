import ActivityKit
import Foundation

/// The pairing Live Activity, shared by the app (which starts and updates it)
/// and the widget extension (which draws it in the Dynamic Island and on the
/// Lock Screen). The code shows up there while the user is in Settings typing it.
struct PairingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Status: String, Codable, Hashable {
            case waiting, code, paired, failed
        }

        var status: Status
        /// The six-digit pairing code, once the other side asks for it.
        var code: String?
    }

    /// Shown on the other device as "Pair with <hostName>".
    var hostName: String
}

extension PairingActivityAttributes.ContentState {
    /// "123456" as "123 456", the way the code is grouped in the app.
    var groupedCode: String? {
        guard let code, code.count == 6 else { return code }
        return "\(code.prefix(3)) \(code.suffix(3))"
    }
}
