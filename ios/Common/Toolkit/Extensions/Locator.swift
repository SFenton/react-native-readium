import Foundation
import R2Shared

extension Locator: Codable {
  public init(from decoder: Decoder) throws {
    let json = try decoder.singleValueContainer().decode(String.self)
    try self.init(jsonString: json)!
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(jsonString)
  }
}

// CFI convenience properties for react-native-readium
extension Locator {
  /// Convenience property to access full CFI from otherLocations
  public var cfi: String? {
    return locations.otherLocations["cfi"] as? String
  }
}
