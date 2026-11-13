import AppKit
import Sparkle

@MainActor
final class UpdateController: NSObject {
  private var controller: SPUStandardUpdaterController?
  func start() {
    let info = Bundle.main.infoDictionary ?? [:]
    guard info["CSToolXUpdatesEnabled"] as? Bool == true,
      let key = info["SUPublicEDKey"] as? String, Data(base64Encoded: key)?.count == 32,
      let feed = info["SUFeedURL"] as? String, let url = URL(string: feed), url.scheme == "https",
      url.host != nil, url.user == nil, url.password == nil,
      info["SUVerifyUpdateBeforeExtraction"] as? Bool == true,
      info["SURequireSignedFeed"] as? Bool == true,
      info["SUSignedFeedFailureExpirationInterval"] as? Int == 0,
      info["SUAllowsAutomaticUpdates"] as? Bool == false
    else { return }
    controller = SPUStandardUpdaterController(
      startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
  }
  @objc func check(_ sender: Any?) {
    guard let controller else {
      let alert = NSAlert()
      alert.messageText = "当前构建未启用更新"
      alert.informativeText = "开发构建不访问更新源。请使用 GitHub Release 中的完整应用。"
      alert.runModal()
      return
    }
    controller.checkForUpdates(sender)
  }
}
