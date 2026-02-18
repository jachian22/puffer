import SwiftUI
import SecureDataFetcherCore

@main
struct SecureDataFetcherApp: App {
    @StateObject private var model = AppModel.makeLiveOrPreview()

    var body: some Scene {
        WindowGroup {
            RootView(model: model, automationSession: model.automationSession)
                .id(ObjectIdentifier(model.automationSession))
        }
    }
}
