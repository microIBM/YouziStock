import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    let launched = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    DispatchQueue.main.async { [weak self] in
      self?.probeNetworkAccess()
    }
    return launched
  }

  // A native request exercises iOS network access; whether a permission
  // prompt appears is decided by the system.
  private func probeNetworkAccess() {
    guard let url = URL(string: "https://captive.apple.com/hotspot-detect.html") else { return }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 10
    configuration.timeoutIntervalForResource = 15
    configuration.urlCache = nil
    configuration.httpCookieStorage = nil
    configuration.urlCredentialStorage = nil
    configuration.waitsForConnectivity = false
    let session = URLSession(configuration: configuration)
    var request = URLRequest(url: url)
    request.cachePolicy = .reloadIgnoringLocalCacheData
    NSLog("[NetworkProbe] Starting native HTTPS connectivity check")
    session.dataTask(with: request) { _, response, error in
      defer { session.finishTasksAndInvalidate() }
      if let error = error as NSError? {
        NSLog("[NetworkProbe] Failed domain=%@ code=%ld message=%@",
              error.domain, error.code, error.localizedDescription)
      } else if let response = response as? HTTPURLResponse {
        NSLog("[NetworkProbe] Completed HTTP %ld", response.statusCode)
      } else {
        NSLog("[NetworkProbe] Completed without HTTP response")
      }
    }.resume()
  }
}
