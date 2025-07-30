import Combine
import Foundation
import R2Shared
import R2Streamer
import UIKit
import R2Navigator


class ReadiumView : UIView, Loggable {
  var readerService: ReaderService = ReaderService()
  var readerViewController: ReaderViewController?
  var viewController: UIViewController? {
    let viewController = sequence(first: self, next: { $0.next }).first(where: { $0 is UIViewController })
    return viewController as? UIViewController
  }
  private var subscriptions = Set<AnyCancellable>()
  private var pendingLocation: NSDictionary? = nil
  private var isNavigatorReady: Bool = false
  private var isNavigatingProgrammatically: Bool = false

  @objc var file: NSDictionary? = nil {
    didSet {
      let initialLocation = file?["initialLocation"] as? NSDictionary
      if let url = file?["url"] as? String {
        self.loadBook(url: url, location: initialLocation)
      }
    }
  }
  @objc var location: NSDictionary? = nil {
    didSet {
      self.updateLocation()
    }
  }
  @objc var preferences: NSString? = nil {
    didSet {
      self.updatePreferences(preferences)
    }
  }
  @objc var onLocationChange: RCTDirectEventBlock?
  @objc var onTableOfContents: RCTDirectEventBlock?

  func loadBook(
    url: String,
    location: NSDictionary?
  ) {
    // Reset navigator ready state
    isNavigatorReady = false

    guard let rootViewController = UIApplication.shared.delegate?.window??.rootViewController else { return }

    self.readerService.buildViewController(
      url: url,
      bookId: url,
      location: location,
      sender: rootViewController,
      completion: { vc in
        self.addViewControllerAsSubview(vc)
      }
    )
  }

  func getLocator() -> Locator? {
    let locator = ReaderService.locatorFromLocation(location, readerViewController?.publication)
    return locator
  }

  func updateLocation() {
    guard let navigator = readerViewController?.navigator else {
      pendingLocation = location
      return;
    }

    // Check if navigator is ready by testing if we can get current location
    if !isNavigatorReady {
      pendingLocation = location
      return;
    }

    guard let locator = self.getLocator() else {
      return;
    }

    let cur = navigator.currentLocation

    if (cur != nil && locator.hashValue == cur?.hashValue) {
      return;
    }

    // Set flag to prevent feedback loop from location change events
    isNavigatingProgrammatically = true

    navigator.go(
      to: locator,
      animated: true
    )
    // Note: Flag will be cleared when navigation completes and location change event is received
  }

  func updatePreferences(_ preferences: NSString?) {

    if (readerViewController == nil) {
      // defer setting update as view isn't initialized yet
      return;
    }

    guard let navigator = readerViewController!.navigator as? EPUBNavigatorViewController else {
      return;
    }

    guard let preferencesJson = preferences as? String else {
      print("TODO: handle error. Bad string conversion for preferences")
      return;
    }

    do {
      let preferences = try JSONDecoder().decode(EPUBPreferences.self, from: Data(preferencesJson.utf8))
      navigator.submitPreferences(preferences)
    } catch {
      print(error)
      print("TODO: handle error. Skipping preferences due to thrown exception")
      return;
    }
  }

  override func removeFromSuperview() {
    readerViewController?.willMove(toParent: nil)
    readerViewController?.view.removeFromSuperview()
    readerViewController?.removeFromParent()

    // cancel all current subscriptions
    for subscription in subscriptions {
      subscription.cancel()
    }
    subscriptions = Set<AnyCancellable>()

    readerViewController = nil
    super.removeFromSuperview()
  }

  private func addViewControllerAsSubview(_ vc: ReaderViewController) {
    vc.publisher.sink(
      receiveValue: { locator in
        // Skip processing location changes during programmatic navigation to prevent feedback loops
        if self.isNavigatingProgrammatically {
          // Clear the flag since navigation has completed (we received a location change)
          self.isNavigatingProgrammatically = false
          return
        }

        // Mark navigator as ready on first location event
        if !self.isNavigatorReady {
          self.isNavigatorReady = true

          // Apply any pending location
          if let pending = self.pendingLocation {
            self.location = pending
            self.pendingLocation = nil
          }
        }

        self.onLocationChange?(locator.json)
      }
    )
    .store(in: &self.subscriptions)

    readerViewController = vc

    // if the controller was just instantiated then apply any existing preferences
    if (preferences != nil) {
      self.updatePreferences(preferences)
    }

    readerViewController!.view.frame = self.superview!.frame
    self.viewController!.addChild(readerViewController!)
    let rootView = self.readerViewController!.view!
    self.addSubview(rootView)
    self.viewController!.addChild(readerViewController!)
    self.readerViewController!.didMove(toParent: self.viewController!)

    // bind the reader's view to be constrained to its parent
    rootView.translatesAutoresizingMaskIntoConstraints = false
    rootView.topAnchor.constraint(equalTo: self.topAnchor).isActive = true
    rootView.bottomAnchor.constraint(equalTo: self.bottomAnchor).isActive = true
    rootView.leftAnchor.constraint(equalTo: self.leftAnchor).isActive = true
    rootView.rightAnchor.constraint(equalTo: self.rightAnchor).isActive = true

    self.onTableOfContents?([
      "toc": vc.publication.tableOfContents.map({ link in
        return link.json
      })
    ])
  }
}
