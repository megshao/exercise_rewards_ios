#!/bin/bash
#
# 產生 Xcode 專案，並把版控中的相依鎖定檔套用進去。
#
# 為什麼需要這支腳本：
#   `.xcodeproj` 由 XcodeGen 產生、不進版控，而 Xcode 把 SPM 的鎖定檔
#   （Package.resolved）放在 `.xcodeproj` 內部，於是它也跟著進不了版控。
#   沒有鎖定檔，`App/project.yml` 寫的 `from: "12.18.0"` 會讓每個人 clone
#   後解析到當下最新的 12.x —— 不同機器建出來的相依版本可能不同，
#   「同一份原始碼建出同樣的東西」就不成立。
#
#   所以把鎖定檔的真本放在 `App/Package.resolved`（有進版控），
#   產生專案後再複製回 Xcode 期望的位置。
#
# 用法：
#   ./Scripts/bootstrap.sh
#
# 要升級相依版本時：
#   1. 改 `App/project.yml` 的版本區間
#   2. 跑 `./Scripts/bootstrap.sh --resolve`（允許重新解析）
#   3. 把更新後的鎖定檔複製回真本：
#      cp App/SportsRewards.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved App/Package.resolved
#   4. commit `App/Package.resolved`，變更才會傳給其他人
#
set -euo pipefail

cd "$(dirname "$0")/.."

LOCKFILE="App/Package.resolved"
DEST_DIR="App/SportsRewards.xcodeproj/project.xcworkspace/xcshareddata/swiftpm"

echo "==> 產生 Xcode 專案"
(cd App && xcodegen generate)

if [ "${1:-}" = "--resolve" ]; then
  echo "==> --resolve：略過套用鎖定檔，讓 Xcode 重新解析相依"
  echo "    解析完記得把結果複製回 $LOCKFILE 並 commit"
  exit 0
fi

if [ ! -f "$LOCKFILE" ]; then
  echo "!! 找不到 $LOCKFILE，相依版本將由 Xcode 自行解析（可能與其他人不同）" >&2
  exit 0
fi

echo "==> 套用相依鎖定檔"
mkdir -p "$DEST_DIR"
cp "$LOCKFILE" "$DEST_DIR/Package.resolved"

# 印出鎖到哪些版本，讓建置紀錄裡看得到（CI 上尤其有用）。
python3 - "$LOCKFILE" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
pins = data.get("pins", [])
print(f"    鎖定 {len(pins)} 個套件：")
for pin in pins:
    state = pin.get("state", {})
    version = state.get("version") or state.get("branch") or "?"
    print(f"      {pin['identity']:<42} {version:<16} {state.get('revision', '')[:12]}")
PY

echo
echo "完成。建置時請加 -disableAutomaticPackageResolution，Xcode 才不會偷偷改寫鎖定檔："
echo "  xcodebuild -project App/SportsRewards.xcodeproj -scheme SportsRewards \\"
echo "    -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \\"
echo "    -disableAutomaticPackageResolution build"
