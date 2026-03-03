cask "focusrite-control-2-volume" do
  version "1.1"
  sha256 :no_check # Updated automatically by release workflow

  url "https://github.com/nickmorozov/FocusriteVolumeControl/releases/download/v#{version}/FocusriteVolumeControl.dmg"
  name "Focusrite Volume Control"
  desc "Control Focusrite Scarlett Solo volume with keyboard media keys"
  homepage "https://nickmorozov.github.io/FocusriteVolumeControl/"

  depends_on macos: ">= :sequoia"

  app "FocusriteVolumeControl.app"

  zap trash: [
    "~/Library/Preferences/net.nickmorozov.FocusriteVolumeControl.plist",
  ]
end
