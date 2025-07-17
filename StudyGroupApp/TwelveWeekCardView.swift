import SwiftUI

struct CardView: View {

    var body: some View {
        NavigationView {
            CardDetailView(member: $member)
        }
    }
}
