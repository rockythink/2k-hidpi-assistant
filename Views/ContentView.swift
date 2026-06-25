import SwiftUI

struct ContentView: View {
    @Bindable var store: DisplayStore

    var body: some View {
        NavigationSplitView {
            List {
                Label(L10n.t("nav.displays", store.language), systemImage: "display.2")
            }
            .navigationTitle(L10n.t("app.name", store.language))
            .listStyle(.sidebar)
        } detail: {
            DisplaysView(store: store)
        }
    }
}
