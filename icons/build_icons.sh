#!/usr/bin/env bash
# Build NCQuickhacks.archive from the SVG sources.
#
# WolvenKit's texture import needs DirectXTex, which is Windows-native, so the
# CLI is built for win-x64 and run under Wine. Everything else (SVG -> PNG) is
# native.
#
#   WK=/path/to/WolvenKit.CLI.exe ./build_icons.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$HERE/../archive/pc/mod"
WORK="${WORK:-$HERE/.build}"
GAME="${GAME:-/mnt/ssd/Cyberpunk 2077/game/prefix/drive_c/game}"
WK="${WK:-}"
export WINEPREFIX="${WINEPREFIX:-/mnt/ssd/Cyberpunk 2077/game/prefix}"
export WINEDEBUG="${WINEDEBUG:--all}"

if [[ -z "$WK" || ! -f "$WK" ]]; then
  echo "error: set WK to the win-x64 WolvenKit.CLI.exe" >&2
  echo "  build it with:" >&2
  echo "  dotnet publish WolvenKit.CLI/WolvenKit.CLI.csproj -c Release -r win-x64 --self-contained true -o <dir>" >&2
  exit 1
fi

# Oodle. WolvenKit loads this from %LOCALAPPDATA%, NOT from beside the exe
# (WolvenKit.Core/Compression/Oodle.cs:88). It normally self-installs by finding
# the game through the registry, which a GOG-under-Wine install does not answer,
# so place it by hand. Without this, packing silently falls back to Kraken.
OODLE="$GAME/bin/x64/oo2ext_7_win64.dll"
if [[ -f "$OODLE" ]]; then
  for u in "$WINEPREFIX"/drive_c/users/*/AppData/Local; do
    [[ -d "$u" && ! -f "$u/oo2ext_7_win64.dll" ]] && cp "$OODLE" "$u/"
  done
else
  echo "warning: $OODLE not found - archive will be Kraken-compressed" >&2
fi

DEPOT="$WORK/NCQuickhacks/base/ncquickhacks/ui"
rm -rf "$WORK"
mkdir -p "$DEPOT" "$OUT"

# 1. SVG -> PNG (straight alpha). No -w/-h: each source carries its own size.
#    The cards are 128x128, the scanner glyphs 64x64, the storefront 256x256,
#    matching what the shipped art uses at each of those three call sites.
for f in "$HERE"/src/*.svg; do
  n="$(basename "$f" .svg)"
  rsvg-convert "$f" -o "$DEPOT/$n.png"
done

# 2. PNG -> XBM
wine "$WK" import "$DEPOT" -o "$DEPOT" 2>&1 | grep -iE "success|error" || true
rm -f "$DEPOT"/*.png

# 3. inkatlas JSON per icon, then JSON -> CR2W
python3 - "$DEPOT" <<'PY'
import json, os, sys, glob

depot = sys.argv[1]
# Filename -> atlas part name. Must match atlasPartName in the tweak YAML.
PARTS = {
    "smartlink_scramble":   "NCQSmartLinkScramble",
    "reflex_jammer":        "NCQReflexJammer",
    "optic_overwrite":      "NCQOpticOverwrite",
    "phantom_overlay":      "NCQPhantomOverlay",
    "motor_cortex":         "NCQMotorCortexInversion",
    "adrenaline_overdose":  "NCQAdrenalineOverdose",
    "crypto_siphon":        "NCQCryptoSiphon",
    "ncq_store":            "NCQStore",
    # Scanner glyphs. The radial menu draws these at 64px, where a full card is
    # an unreadable smudge, so they get their own icon record - the same split
    # the shipped art makes between item_icons18 and quickhacks_icons.
    "smartlink_scramble_scanner":  "NCQSmartLinkScrambleScanner",
    "reflex_jammer_scanner":       "NCQReflexJammerScanner",
    "optic_overwrite_scanner":     "NCQOpticOverwriteScanner",
    "phantom_overlay_scanner":     "NCQPhantomOverlayScanner",
    "motor_cortex_scanner":        "NCQMotorCortexInversionScanner",
    "adrenaline_overdose_scanner": "NCQAdrenalineOverdoseScanner",
    "crypto_siphon_scanner":       "NCQCryptoSiphonScanner",
}

# The inventory card is authored 99x128 - the size the shipped part measures -
# but a texture has to stay a power of two, so it is drawn at x=14 inside a
# 128px canvas and the atlas samples just that window back out. Sampling the
# full 0..1 would stretch the card square and is what made the first pass look
# wrong. Everything else fills its texture.
CARD_UV = {"$type": "RectF", "Left": 14 / 128, "Right": 113 / 128, "Top": 0, "Bottom": 1}
FULL_UV = {"$type": "RectF", "Left": 0, "Right": 1, "Top": 0, "Bottom": 1}

missing = [n for n in PARTS if not os.path.exists(os.path.join(depot, n + ".xbm"))]
orphans = [os.path.basename(p)[:-4] for p in glob.glob(os.path.join(depot, "*.xbm"))
           if os.path.basename(p)[:-4] not in PARTS]
if missing or orphans:
    sys.exit(f"part map out of sync: missing xbm for {missing}, xbm with no part name {orphans}")

def slot(depot_path, part, uv):
    return {
        "$type": "inkTextureSlot",
        "parts": [{
            "$type": "inkTextureAtlasMapper",
            "clippingRectInPixels": {"$type": "Rect", "bottom": 0, "left": 0, "right": 0, "top": 0},
            "clippingRectInUVCoords": dict(uv),
            "partName": {"$type": "CName", "$storage": "string", "$value": part},
        }],
        "slices": [],
        "texture": {"DepotPath": {"$type": "ResourcePath", "$storage": "string",
                                  "$value": depot_path}, "Flags": "Soft"},
    }

EMPTY = {"DepotPath": {"$type": "ResourcePath", "$storage": "uint64", "$value": "0"}, "Flags": "Soft"}

for name, part in PARTS.items():
    uv = FULL_UV if name.endswith("_scanner") or name == "ncq_store" else CARD_UV
    xbm = f"base\\\\ncquickhacks\\\\ui\\\\{name}.xbm"
    doc = {
        "Header": {"WolvenKitVersion": "8.19.1", "WKitJsonVersion": "0.0.9",
                   "GameVersion": 2310, "DataType": "CR2W"},
        "Data": {"Version": 195, "BuildVersion": 0, "RootChunk": {
            "$type": "inkTextureAtlas",
            "activeTexture": "StaticTexture",
            "cookingPlatform": "PLATFORM_PC",
            "dynamicTexture": dict(EMPTY),
            "dynamicTextureSlot": {"$type": "inkDynamicTextureSlot", "parts": [],
                                   "texture": dict(EMPTY)},
            "isSingleTextureMode": 1,
            "parts": [], "slices": [],
            "slots": {"Elements": [
                slot(xbm, part, uv),
                slot(xbm, part, uv),
                {"$type": "inkTextureSlot", "parts": [], "slices": [], "texture": dict(EMPTY)},
            ]},
            "texture": dict(EMPTY),
            "textureResolution": "UltraHD_3840_2160",
        }, "EmbeddedFiles": []},
    }
    with open(os.path.join(depot, f"{name}.inkatlas.json"), "w") as fh:
        json.dump(doc, fh, indent=2)
PY

wine "$WK" convert deserialize "$DEPOT" -o "$DEPOT" 2>&1 | grep -iE "success|error" || true
rm -f "$DEPOT"/*.json

# 4. Localization. Names and tooltips are secondary keys resolved by these,
#    registered through NCQuickhacks.archive.xl.
LOCAL="$WORK/NCQuickhacks/base/ncquickhacks/local"
python3 "$HERE/../loc/build_locale.py" "$LOCAL"
wine "$WK" convert deserialize "$LOCAL" -o "$LOCAL" 2>&1 | grep -iE "success|error" || true
# Delete ONLY the sidecars. Every WolvenKit sidecar is <name>.<ext>.json (two
# dots); the built resource is en-us.json (one). A blanket *.json here would
# eat the very files we just made.
find "$LOCAL" -name "*.*.json" -delete

# 5. Pack
wine "$WK" pack "$WORK/NCQuickhacks" -o "$OUT" 2>&1 | grep -iE "success|error" || true

ls -la "$OUT"
