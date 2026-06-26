import SwiftUI

struct ContentView: View {
    @Bindable var store: DisplayStore

    var body: some View {
        SettingsView(store: store)
    }
}
