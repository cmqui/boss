class Bossctl < Formula
  desc "CLI for controlling Bose devices through the shared libboss runtime"
  homepage "https://github.com/cmqui/boss"
  version "0.1.0"
  license "MIT"

  depends_on "libboss"

  if Hardware::CPU.arm?
    url "https://github.com/cmqui/boss/releases/download/v#{version}/bossctl-#{version}-macos-arm64.tar.gz"
    sha256 "0757cd1470ccbbf116d8a2557149a72a20525ac47775510a66cc10de955ddc5f"
  else
    url "https://github.com/cmqui/boss/releases/download/v#{version}/bossctl-#{version}-macos-x86_64.tar.gz"
    sha256 "f1d6348e8f5c3a8f3f5a5a7c29849f020c0b0deb17dc301b118e2c98ace0e672"
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
