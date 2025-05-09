import Foundation

struct Appointments: Identifiable, Decodable {
    var id: Int
    var date: String
    var time: String
    var clinic: String
    var status: String
    var description: String?
}
