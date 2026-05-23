cask "boss-ui" do
  version "0.0.0"
  sha256 "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"

  url "https://github.com/cmqui/boss/releases/download/v#{version}/boss-ui-#{version}-macos-universal.zip"
  name "Boss UI"
  desc "App for controlling Bose devices through libboss"
  homepage "https://github.com/cmqui/boss"

  depends_on :macos
  depends_on formula: "libboss"

  app "Boss.app"
end
