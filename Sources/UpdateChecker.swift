import Cocoa

struct UpdateInfo {
    let version: String
    let url: String
}

/// 只在你手动点击「检查更新」时访问 GitHub Releases API。
/// 不做后台轮询，不上传任何信息。
enum UpdateChecker {
    private static let latestReleaseAPI = "https://api.github.com/repos/pandengyao/PowerLock/releases/latest"

    static func check(completion: @escaping (UpdateInfo?) -> Void) {
        guard let url = URL(string: latestReleaseAPI) else {
            completion(nil)
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = object["tag_name"] as? String,
                  let htmlURL = object["html_url"] as? String else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            DispatchQueue.main.async {
                completion(UpdateInfo(version: version, url: htmlURL))
            }
        }.resume()
    }
}
