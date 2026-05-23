class Bossctl < Formula
  desc "CLI for controlling Bose devices through the shared libboss runtime"
  homepage "https://github.com/cmqui/boss"
  version "0.0.0"
  license "MIT"

  depends_on "libboss"

  if Hardware::CPU.arm?
    url "https://github.com/cmqui/boss/releases/download/v#{version}/bossctl-#{version}-macos-arm64.tar.gz"
    sha256 "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
  else
    url "https://github.com/cmqui/boss/releases/download/v#{version}/bossctl-#{version}-macos-x86_64.tar.gz"
    sha256 "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
  end

  def install
    libexec.install "bossctl"
    (bin/"bossctl").write_env_script libexec/"bossctl", "LIBBOSS_FFI_HOMEBREW_PREFIX" => Formula["libboss"].opt_prefix
  end

  test do
    assert_path_exists bin/"bossctl"
    assert_path_exists Formula["libboss"].opt_lib/"libboss_ffi.dylib"
  end
end
