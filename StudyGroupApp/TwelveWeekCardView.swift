import SwiftUI

struct CardView: View {
    @State private var member = TwelveWeekMember(name: "DJ", goals: [])

    var body: some View {
        NavigationView {
            CardDetailView(member: $member)
        }
    }
}
