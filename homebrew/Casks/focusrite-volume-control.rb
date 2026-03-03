cask "focusrite-volume-control" do
  version "1.2"
  sha256 :no_check # Updated automatically by release workflow

  url "https://github.com/enum-solutions-inc/focusrite-volume-control/releases/download/v#{version}/FocusriteVolumeControl.dmg"
  name "Focusrite Volume Control"
  desc "Control Focusrite Scarlett 4th gen volume with media keys via Focusrite Control 2"
  homepage "https://enum-solutions-inc.github.io/focusrite-volume-control/"

  depends_on macos: ">= :sequoia"

  app "Focusrite Volume Control.app"

  zap trash: [
    "~/Library/Preferences/net.nickmorozov.FocusriteVolumeControl.plist",
  ]
end
