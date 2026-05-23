cask "boss-ui" do
  version "0.1.0"
  sha256 "e882d63db9e4ec7dc71822d55118a470c15a89d766c324e85dd479781d5b5e3e"

  url "https://github.com/cmqui/boss/releases/download/v#{version}/boss-ui-#{version}-macos-universal.zip"
  name "Boss UI"
  desc "App for controlling Bose devices through libboss"
  homepage "https://github.com/cmqui/boss"

  depends_on :macos
  depends_on formula: "libboss"

  app "Boss.app"
end
