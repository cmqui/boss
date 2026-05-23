class Libboss < Formula
  desc "Shared Rust runtime for bossctl and boss-ui"
  homepage "https://github.com/cmqui/boss"
  version "0.0.0"
  license "MIT"

  if Hardware::CPU.arm?
    url "https://github.com/cmqui/boss/releases/download/v#{version}/libboss-#{version}-macos-arm64.tar.gz"
    sha256 "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  else
    url "https://github.com/cmqui/boss/releases/download/v#{version}/libboss-#{version}-macos-x86_64.tar.gz"
    sha256 "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  end

  def install
    lib.install "libboss_ffi.dylib"
  end

  test do
    assert_path_exists lib/"libboss_ffi.dylib"
  end
end
