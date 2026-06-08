import SwiftUI

extension String {
    func localized() -> String {
        NSLocalizedString(self, comment: "")
    }
}

extension View {
    func localizedText(_ key: String) -> Text {
        Text(key.localized())
    }
}

struct LocalizedText: View {
    let key: String
    
    var body: Text {
        Text(key.localized())
    }
}