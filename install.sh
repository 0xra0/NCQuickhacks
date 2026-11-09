#!/usr/bin/env bash
# Install / uninstall NCQuickhacks into the Cyberpunk 2077 prefix.
#   ./install.sh            install
#   ./install.sh uninstall  remove
set -euo pipefail

GAME="${GAME:-/mnt/ssd/Cyberpunk 2077/game/prefix/drive_c/game}"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -d "$GAME/r6/scripts" ]]; then
  echo "error: game not found at $GAME (override with GAME=...)" >&2
  exit 1
fi

if [[ "${1:-install}" == "uninstall" ]]; then
  rm -rf "$GAME/r6/scripts/NCQuickhacks" "$GAME/r6/tweaks/NCQuickhacks"
  rm -f "$GAME/archive/pc/mod/NCQuickhacks.archive" \
        "$GAME/archive/pc/mod/NCQuickhacks.archive.xl"
  echo "removed NCQuickhacks"
  exit 0
fi

# Virtual Atelier is the mod's only cross-mod dependency, and it is confined to
# NCQuickhacks_atelier.reds. If VA is absent, VirtualShopRegistration does not
# resolve and redscript aborts the WHOLE r6/scripts compile - taking every other
# script mod down with it. So detect it and stage only what will compile.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp "$SRC/r6/scripts/NCQuickhacks/"*.reds "$STAGE/"

if grep -rqs "class VirtualShopRegistration" "$GAME/r6/scripts/"; then
  echo "Virtual Atelier found - including the storefront"
else
  rm -f "$STAGE/NCQuickhacks_atelier.reds"
  echo "Virtual Atelier not found - skipping the storefront (netrunner vendors still work)"
fi

# Lint what we are actually about to deploy. Prefer the modded bundle: it is
# the post-compile output of the last launch, so it knows about other mods'
# types and RED4ext natives. Vanilla final.redscripts does not.
LINTER="${LINTER:-/mnt/sata/redscript/target/release/redscript-cli}"
BUNDLE="$GAME/r6/cache/final.redscripts.modded"
[[ -f "$BUNDLE" ]] || BUNDLE="$GAME/r6/cache/final.redscripts"

# On a REINSTALL the modded bundle already contains our own previous build, so
# every @addField/@addMethod/@wrapMethod of ours comes back as a duplicate.
# Those two codes are self-conflicts, not defects - ignore them, and only them.
# Any other diagnostic still refuses the install.
SELF_CONFLICT="DUP_FN_ANN|ADD_FIELD_CONFLICT"

if [[ -x "$LINTER" ]]; then
  echo "linting against $(basename "$BUNDLE")..."
  # `|| true`: the linter exits non-zero on any diagnostic, and `set -o pipefail`
  # would otherwise propagate that and abort here before we can classify them.
  OUT="$({ "$LINTER" lint -s "$STAGE" -b "$BUNDLE" 2>&1 || true; } |
         sed 's/\x1b\[[0-9;]*m//g' | grep -vE "TRACE|DEBUG" || true)"

  if [[ -d "$GAME/r6/scripts/NCQuickhacks" ]]; then
    REAL="$(grep -E "^\[ERROR\]" <<<"$OUT" | grep -vE "\[($SELF_CONFLICT)\]" || true)"
    SELF="$(grep -cE "\[($SELF_CONFLICT)\]" <<<"$OUT" || true)"
    # `&& echo` alone returns non-zero when the count is 0, which set -e kills.
    if [[ "$SELF" -gt 0 ]]; then
      echo "  ($SELF self-conflict(s) ignored - already installed)"
    fi
  else
    REAL="$(grep -E "^\[ERROR\]" <<<"$OUT" || true)"
  fi

  grep -E "^\[(WARN|INFO)\]" <<<"$OUT" | grep -vE "\[($SELF_CONFLICT)\]" || true
  if [[ -n "$REAL" ]]; then
    echo "$REAL" >&2
    echo "error: lint failed, refusing to install" >&2
    exit 1
  fi
  echo "  lint clean"
else
  echo "warning: linter not found at $LINTER, skipping pre-flight check" >&2
fi

if [[ ! -f "$SRC/archive/pc/mod/NCQuickhacks.archive" ]]; then
  echo "error: NCQuickhacks.archive missing, run icons/build_icons.sh first" >&2
  exit 1
fi

mkdir -p "$GAME/r6/scripts/NCQuickhacks" "$GAME/r6/tweaks/NCQuickhacks" "$GAME/archive/pc/mod"
# Clear first: a stale NCQuickhacks_atelier.reds from a previous install would
# survive an overwrite-only copy and break the compile if VA has since been removed.
rm -f "$GAME/r6/scripts/NCQuickhacks/"*.reds
cp "$STAGE/"*.reds "$GAME/r6/scripts/NCQuickhacks/"
# The weapon-mod tweaks $base records that "Quickhack Weapon Mods" (Nexus
# 24568) defines. Without it TweakXL logs unresolved bases for all 7, so ship
# it only when that mod is installed. Same staging idea as the Atelier script.
YSTAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE" "$YSTAGE"' EXIT
cp "$SRC/r6/tweaks/NCQuickhacks/"*.yaml "$YSTAGE/"
if [[ -f "$GAME/r6/scripts/Quickhack Weapon Mods.reds" ]]; then
  echo "Quickhack Weapon Mods found - including the weapon-mod variants"
else
  rm -f "$YSTAGE/NCQuickhacks_weaponmods.yaml"
  echo "Quickhack Weapon Mods not found - skipping the weapon-mod variants"
fi

rm -f "$GAME/r6/tweaks/NCQuickhacks/"*.yaml
cp "$YSTAGE/"*.yaml "$GAME/r6/tweaks/NCQuickhacks/"
cp "$SRC/archive/pc/mod/NCQuickhacks.archive" "$GAME/archive/pc/mod/"
# The .xl registers the localization resources. Without it every quickhack name
# and tooltip resolves to an empty string, since the YAML holds only keys.
cp "$SRC/archive/pc/mod/NCQuickhacks.archive.xl" "$GAME/archive/pc/mod/"

echo "installed NCQuickhacks"
echo "  scripts -> $GAME/r6/scripts/NCQuickhacks"
echo "  tweaks  -> $GAME/r6/tweaks/NCQuickhacks"
echo "  archive -> $GAME/archive/pc/mod/NCQuickhacks.archive"
echo
echo "In game, buy them from any of these:"
echo "  - the 'Night City Quickhacks' store in Virtual Atelier (if installed)"
echo "  - any of 7 netrunner ripperdocs, or BlackMarketer_HUB"
echo
echo "Or grab them directly with CET:"
echo '  Game.AddToInventory("Items.NCQ_SmartLinkScrambleProgram")'
