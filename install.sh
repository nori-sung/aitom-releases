#!/bin/sh
# AItom installer for macOS (DESIGN §4.19 처음 설치, TECH_STACK §8 설치 명령). Run in Terminal:
#   curl -fsSL https://raw.githubusercontent.com/nori-sung/aitom-releases/main/install.sh | bash
# Files fetched with curl carry no quarantine flag, so the unsigned app opens without the Gatekeeper prompt.
set -eu

REPO=nori-sung/aitom-releases
DIR=${AITOM_INSTALL_DIR:-/Applications}

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

[ "$(uname -s)" = Darwin ] && [ "$(sysctl -n hw.optional.arm64 2>/dev/null || echo 0)" = 1 ] ||
  fail "AItom은 Apple Silicon이 탑재된 Mac에만 설치할 수 있습니다."

TMP=$(mktemp -d)
MNT="$TMP/mnt"
cleanup() {
  [ -d "$MNT" ] && hdiutil detach "$MNT" -quiet 2>/dev/null
  rm -rf "$TMP"
}
trap cleanup EXIT

curl -fsL -H 'Accept: application/vnd.github+json' -H 'User-Agent: AItom' -o "$TMP/release.json" \
  "https://api.github.com/repos/$REPO/releases/latest" || fail "GitHub에 연결할 수 없습니다."

# version, download URL and SHA-256 of this Mac's file, the same way the app's updater picks them (src/main/update.ts)
INFO=$(osascript -l JavaScript - "$TMP/release.json" <<'JS'
function run(argv) {
  const text = $.NSString.stringWithContentsOfFileEncodingError(argv[0], $.NSUTF8StringEncoding, null).js
  const r = JSON.parse(text)
  const v = String(r.tag_name || '').replace(/^v/, '')
  const name = `AItom-${v}-mac-arm64.dmg`
  const a = (r.assets || []).find((x) => x.name === name)
  if (!a) return ''
  let sha = ((a.digest || '').match(/^sha256:([0-9a-f]{64})$/i) || [])[1]
  if (!sha) {
    const esc = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
    sha = ((r.body || '').match(new RegExp(`^([0-9a-f]{64})\\s+\\*?${esc}\\s*$`, 'mi')) || [])[1]
  }
  return sha ? [v, name, a.browser_download_url, sha.toLowerCase()].join(' ') : ''
}
JS
) || INFO=''
[ -n "$INFO" ] || fail "최신 릴리스에는 이 컴퓨터에 대한 설치 프로그램이 없습니다."
set -- $INFO
VERSION=$1 NAME=$2 URL=$3 SHA=$4

pgrep -f "$DIR/AItom.app/Contents/MacOS/AItom" >/dev/null 2>&1 &&
  fail "AItom이 실행 중입니다. AItom을 종료하고 이 명령을 다시 실행하십시오."
[ -w "$DIR" ] || fail "$DIR 폴더에 쓸 수 없습니다."

printf '%s\n' "AItom $VERSION 다운로드 중..."
curl -fL --progress-bar -o "$TMP/$NAME" "$URL" || fail "AItom을 다운로드할 수 없습니다."
[ "$(shasum -a 256 "$TMP/$NAME" | cut -d ' ' -f 1)" = "$SHA" ] ||
  fail "다운로드한 파일이 릴리스의 체크섬과 일치하지 않습니다."

printf '%s\n' "설치 중..."
mkdir "$MNT"
hdiutil attach -nobrowse -readonly -noautoopen -mountpoint "$MNT" "$TMP/$NAME" >/dev/null 2>&1 || fail "설치에 실패했습니다."
[ -d "$MNT/AItom.app" ] || fail "설치에 실패했습니다."
rm -rf "$DIR/AItom.app.new"
ditto "$MNT/AItom.app" "$DIR/AItom.app.new" || fail "설치에 실패했습니다."
rm -rf "$DIR/AItom.app"
mv "$DIR/AItom.app.new" "$DIR/AItom.app"

printf '%s\n' "설치 완료: AItom $VERSION"
