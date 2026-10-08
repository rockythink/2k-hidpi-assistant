import SwiftUI

struct ContentView: View {
    @Bindable var store: DisplayStore

    var body: some View {
        SettingsView(store: store)
            .background(AppTheme.background)
            .tint(AppTheme.accent)
            .accentColor(AppTheme.accent)
    }
}
