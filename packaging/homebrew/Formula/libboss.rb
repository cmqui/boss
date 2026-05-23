class Libboss < Formula
  desc "Shared Rust runtime for bossctl and boss-ui"
  homepage "https://github.com/cmqui/boss"
  version "0.1.0"
  license "MIT"

  if Hardware::CPU.arm?
    url "https://github.com/cmqui/boss/releases/download/v#{version}/libboss-#{version}-macos-arm64.tar.gz"
    sha256 "e31e9948a1ff63ffce249293dab151db6bc6f98f6ada1a54757355c8884b245a"
  else
    url "https://github.com/cmqui/boss/releases/download/v#{version}/libboss-#{version}-macos-x86_64.tar.gz"
    sha256 "34e2b62054015b79887dd26e01df8517dab159dd0ca4e3b5d0e3e94f84d4be1d"
  end

  def install
    lib.install "libboss_ffi.dylib"
  end

  test do
    assert_path_exists lib/"libboss_ffi.dylib"
  end
end
