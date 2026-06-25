import SwiftUI

struct ContentView: View {
    @Bindable var store: DisplayStore

    var body: some View {
        DisplaysView(store: store)
    }
}
