# Homebrew Cask 模板
# 发布到 GitHub Releases 后，把 OWNER、版本和 sha256 换成实际值，
# 放进自己的 homebrew tap（例如 homebrew-tap/Casks/powerlock.rb）。
#
# 注意：助手是系统级 launchd 服务，建议先让用户在 App 菜单里
# 执行「卸载后台助手…」再删除 App，避免残留。
cask "powerlock" do
  version "1.0.0"
  sha256 "REPLACE_WITH_SHA256_OF_DMG"

  url "https://github.com/OWNER/PowerLock/releases/download/v#{version}/PowerLock-#{version}.dmg"
  name "PowerLock"
  desc "Keep your Mac awake and unlocked while on AC power"
  homepage "https://github.com/OWNER/PowerLock"

  app "PowerLock.app"

  zap trash: [
    "~/Library/Application Support/PowerLock",
    "~/Library/LaunchAgents/com.powerlock.login.plist",
    "~/Library/Logs/PowerLock.log"
  ]
end
