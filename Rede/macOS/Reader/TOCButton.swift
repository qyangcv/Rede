import SwiftUI

struct TOCButton: View {
    @Binding var isPresented: Bool

    var body: some View {
        Button("目录", systemImage: "list.bullet") {
            isPresented.toggle()
        }
        .help("目录")
    }
}
