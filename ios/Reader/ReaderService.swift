import Combine
import Foundation
import R2Shared
import R2Streamer
import UIKit

final class ReaderService: Loggable {
  var app: AppModule?
  var streamer = Streamer()
  private var subscriptions = Set<AnyCancellable>()

  init() {
    do {
      self.app = try AppModule()
    } catch {
      print("TODO: An error occurred instantiating the ReaderService")
      print(error)
    }
  }

  /// Validates whether a CFI string represents a complete, valid CFI that warrants precision navigation
  /// This helps distinguish between meaningful user-provided CFIs and auto-generated position CFIs
  private static func isCompleteValidCFI(_ cfi: String) -> Bool {
    // A complete CFI should:
    // 1. Start with "epubcfi("
    // 2. Have meaningful depth (more than just spine reference)
    // 3. Have structural navigation components
    // 4. Not be a simple auto-generated position CFI

    guard cfi.hasPrefix("epubcfi(") && cfi.hasSuffix(")") else {
      return false
    }

    let cfiContent = String(cfi.dropFirst(8).dropLast(1)) // Remove "epubcfi(" and ")"

    // Split by '!' to separate spine from document paths
    let parts = cfiContent.split(separator: "!")
    guard parts.count >= 2 else {
      return false
    }

    let documentPath = String(parts[1])

    // Check for meaningful structural depth
    // A simple position CFI like "/4/2:0" should be rejected
    // A meaningful CFI should have multiple levels like "/4/2/58/1:528" or "/4[id]/2/58/1"
    let pathComponents = documentPath.split(separator: "/").filter { !$0.isEmpty }

    // Count meaningful path components
    var meaningfulComponents = 0
    var hasCharacterOffset = false
    var hasElementIds = false

    for component in pathComponents {
      let componentStr = String(component)

      // Check for character offset (like "1:528")
      if componentStr.contains(":") {
        let offsetParts = componentStr.split(separator: ":")
        if offsetParts.count == 2, let offset = Int(offsetParts[1]), offset > 0 {
          hasCharacterOffset = true
          meaningfulComponents += 1
          continue
        }
      }

      // Check for element IDs (like "4[id]")
      if componentStr.contains("[") && componentStr.contains("]") {
        hasElementIds = true
        meaningfulComponents += 1
        continue
      }

      // Check for simple numeric components
      if Int(componentStr) != nil {
        meaningfulComponents += 1
      }
    }

    // Require meaningful depth for precision navigation
    let isValid = meaningfulComponents >= 3 || hasCharacterOffset || hasElementIds

    return isValid
  }

  static func locatorFromLocation(
    _ location: NSDictionary?,
    _ publication: Publication?
  ) -> Locator? {
    guard location != nil else {
      return nil
    }

    let hasLocations = location?["locations"] != nil
    let hasType = (location?["type"] as? String)?.isEmpty == false
    let hasChildren = location?["children"] != nil
    let hasHashHref = (location?["href"] as? String)?.contains("#") == true
    let hasTemplated = location?["templated"] != nil

    // check that we're not dealing with a Link
    if ((!hasType || hasChildren || hasHashHref || hasTemplated) && !hasLocations) {
      guard let publication = publication else {
        return nil
      }
      guard let link = try? Link(json: location) else {
        return nil
      }

      let locator = publication.locate(link)
      return locator
    } else {
      // If we have a publication and CFI data, validate it before attempting enhanced CFI parsing
      if let locations = location?["locations"] as? NSDictionary,
         let cfi = locations["cfi"] as? String,
         let publication = publication {

        // Validate if this is a complete, meaningful CFI that warrants precision navigation
        let isValidFullCFI = isCompleteValidCFI(cfi)

        if isValidFullCFI {
          let locator = Locator.fromCFI(cfi, publication: publication)
          if let enhancedLocator = locator {
            return enhancedLocator
          }
        }
      }

      // Try to create locator from JSON as fallback
      if let locator = try? Locator(json: location) {
        return locator
      }

      // If JSON creation fails, try to handle CFI-based location
      if let locations = location?["locations"] as? NSDictionary {
        if let cfi = locations["cfi"] as? String {
          let locator = Locator.fromCFI(cfi, publication: publication)
          return locator
        }
      }
    }

    return nil
  }

  func buildViewController(
    url: String,
    bookId: String,
    location: NSDictionary?,
    sender: UIViewController?,
    completion: @escaping (ReaderViewController) -> Void
  ) {
    guard let reader = self.app?.reader else {
      return
    }

    self.url(path: url)
      .flatMap { self.openPublication(at: $0, allowUserInteraction: true, sender: sender ) }
      .flatMap { (pub, _) in self.checkIsReadable(publication: pub) }
      .sink(
        receiveCompletion: { error in
          print(">>>>>>>>>>> TODO: handle me", error)
        },
        receiveValue: { pub in
          let locator: Locator? = ReaderService.locatorFromLocation(location, pub)

          let vc = reader.getViewController(
            for: pub,
            bookId: bookId,
            locator: locator
          )

          if (vc != nil) {
            completion(vc!)
          }
        }
      )
      .store(in: &subscriptions)
  }

  func url(path: String) -> AnyPublisher<URL, ReaderError> {
    // Absolute URL.
    if let url = URL(string: path), url.scheme != nil {
      return .just(url)
    }

    // Absolute file path.
    if path.hasPrefix("/") {
      return .just(URL(fileURLWithPath: path))
    }

    return .fail(ReaderError.fileNotFound(fatalError("Unable to locate file: " + path)))
  }

  private func openPublication(
    at url: URL,
    allowUserInteraction: Bool,
    sender: UIViewController?
  ) -> AnyPublisher<(Publication, MediaType), ReaderError> {
    let openFuture = Future<(Publication, MediaType), ReaderError>(
      on: .global(),
      { promise in
        let asset = FileAsset(url: url)
        guard let mediaType = asset.mediaType() else {
          promise(.failure(.openFailed(Publication.OpeningError.unsupportedFormat)))
          return
        }

        self.streamer.open(
          asset: asset,
          allowUserInteraction: allowUserInteraction,
          sender: sender
        ) { result in
          switch result {
          case .success(let publication):
            promise(.success((publication, mediaType)))
          case .failure(let error):
            promise(.failure(.openFailed(error)))
          case .cancelled:
            promise(.failure(.cancelled))
          }
        }
      }
    )

    return openFuture.eraseToAnyPublisher()
  }

  private func checkIsReadable(publication: Publication) -> AnyPublisher<Publication, ReaderError> {
    guard !publication.isRestricted else {
      if let error = publication.protectionError {
        return .fail(.openFailed(error))
      } else {
        return .fail(.cancelled)
      }
    }
    return .just(publication)
  }
}
