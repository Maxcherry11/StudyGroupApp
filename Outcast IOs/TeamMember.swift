//
//  TeamMember.swift
//  Outcast
//
//  Created by D.J. Jones on 5/11/25.
//

import Foundation

class TeamMember: Identifiable, ObservableObject {
    let id: UUID
    @Published var name: String
    @Published var quotesToday: Int
    @Published var salesWTD: Int
    @Published var salesMTD: Int
    @Published var quotesGoal: Int
    @Published var salesWTDGoal: Int
    @Published var salesMTDGoal: Int
    @Published var emoji: String
    @Published var sortIndex: Int

    init(
        id: UUID = UUID(),
        name: String,
        quotesToday: Int,
        salesWTD: Int,
        salesMTD: Int,
        quotesGoal: Int,
        salesWTDGoal: Int,
        salesMTDGoal: Int,
        emoji: String,
        sortIndex: Int
    ) {
        self.id = id
        self.name = name
        self.quotesToday = quotesToday
        self.salesWTD = salesWTD
        self.salesMTD = salesMTD
        self.quotesGoal = quotesGoal
        self.salesWTDGoal = salesWTDGoal
        self.salesMTDGoal = salesMTDGoal
        self.emoji = emoji
        self.sortIndex = sortIndex
    }
}
