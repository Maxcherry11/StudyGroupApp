//
//  LaunchScreenView.swift
//  StudyGroupApp
//
//  Created by D.J. Jones on 5/25/25.
//

import SwiftUI

struct LaunchScreenView: View {
    var body: some View {
        Color(.systemBackground)
            .edgesIgnoringSafeArea(.all)
            .overlay(
                Image("Outcast")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
            )
    }
}

struct LaunchScreenView_Previews: PreviewProvider {
    static var previews: some View {
        LaunchScreenView()
    }
}
