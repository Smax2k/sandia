#!/bin/bash
# Prints the Homebrew cask for a release: scripts/render-cask.sh <version> <dmg-sha256>
set -euo pipefail

VERSION="$1"
SHA256="$2"

cat <<CASK
cask "dvsk" do
  version "$VERSION"
  sha256 "$SHA256"

  url "https://github.com/fabianwgl/dvsk/releases/download/v#{version}/Sandia-#{version}.dmg"
  name "Sandia"
  desc "Open-source f.lux alternative that warms the screen in the evening"
  homepage "https://github.com/fabianwgl/dvsk"

  depends_on macos: :sequoia

  app "Sandia.app"

  uninstall quit: "dev.fwgl.dvsk"

  zap trash: "~/Library/Preferences/dev.fwgl.dvsk.plist"
end
CASK
