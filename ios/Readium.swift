import Foundation
import UIKit

@objc(Readium)
class Readium: NSObject {
  // This is the main entry point for the Readium module
  // React Native will look for this class when initializing the native module
  
  @objc
  static func requiresMainQueueSetup() -> Bool {
    return false
  }
}
