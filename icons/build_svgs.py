import io, os, sys

# ---------------------------------------------------------------- palette
# Re-sampled from in-game photographs of the vanilla quickhack shards (see
# icons/REFERENCE.md).  The shard is drawn in ONE bright cyan; the only other
# ink is the little gold tick strip riding on the frame's top edge.
RIM   = "#6DFFFF"   # (109,255,255) neon outline AND pictogram - one colour
ART   = "#7DEFF7"   # scanner glyph, a shade calmer than the card
PIN   = "#DBA255"   # (219,162,85) gold header tick
PANEL = "#04070A"   # interior wash - translucent, the rarity tint shows through

# ------------------------------------------------------------- geometry
# Card-local coordinates. The card is 99 wide x 128 tall and gets placed at
# x=14 inside a 128x128 texture, which keeps the texture a power of two while
# leaving the atlas part itself at the vanilla 99:128.
CARD_W, CARD_H = 99, 128
CARD_X = 14

# The neon outline. Square top-left, a long 45 chamfer on the top-right, and a
# bottom edge that steps UP in the middle to seat the plinth. Nothing is drawn
# outside it: vanilla lets the rarity tile show around the shard.
RIM_PATH = ("M 9 19 L 79 19 L 97 37 L 97 117 L 78 117 "
            "L 68 108 L 30 108 L 22 117 L 9 117 Z")

# (x, width) of the gold header ticks. Two long blocks and a short one, sitting
# ON the frame's top edge and stopping well short of the chamfer.
HEADER = [(12, 24), (40, 15), (58, 16)]

# The bottom-centre segment of the outline is drawn as a thick filled bar, not
# a stroke - that heavy plinth is the shard's most recognisable tell in game.
PLINTH = (27, 103.5, 44, 6.5)   # x, y, w, h

# Pictogram authoring box, inside the panel: x 16..83, y 26..102.
PCX, PCY = 49.5, 64.0
PBOX_W, PBOX_H = 68.0, 76.0


def frame() -> str:
    """Outline, header ticks, plinth. The glow pass is a wide translucent copy
    under the bright one - cheaper and more predictable through rsvg than an
    SVG blur filter, and it is what gives the edge its bloom in game."""
    ticks = "\n  ".join(
        f'<rect x="{x}" y="11.5" width="{w}" height="6.0" fill="{PIN}"/>'
        for x, w in HEADER)
    px, py, pw, ph = PLINTH
    return f'''<defs>
    <clipPath id="panelclip"><path d="{RIM_PATH}"/></clipPath>
  </defs>
  <path d="{RIM_PATH}" fill="{PANEL}" fill-opacity="0.5"/>
  {ticks}
  <path d="{RIM_PATH}" fill="none" stroke="{RIM}" stroke-width="9.5"
        stroke-opacity="0.16"/>
  <path d="{RIM_PATH}" fill="none" stroke="{RIM}" stroke-width="4.4"/>
  <rect x="{px}" y="{py}" width="{pw}" height="{ph}" fill="{RIM}"/>'''


def via(x, y, r=1.9):
    return f'<circle cx="{x}" cy="{y}" r="{r}" fill="none" stroke="@C@" stroke-width="@SW@"/>'


# The motif now fills the panel edge to edge, the way the shipped shards do:
# one bold glyph on an empty field. Nudged up a little to clear the plinth.
MOTIF_SCALE = 0.98
MOTIF_CY = 61.0


PICTOGRAMS = {
    # Smart-link handshake broken: the lock brackets sit out of register and
    # the guided round leaves along the wrong trace.
    "smartlink_scramble": f'''
  <path d="M 22 40 L 22 30 L 34 30 M 65 30 L 77 30 L 77 40" stroke="@C@" stroke-width="@SW@"/>
  <path d="M 24 88 L 24 98 L 36 98 M 63 98 L 75 98 L 75 88" stroke="@C@" stroke-width="@SW@"/>
  <rect x="42" y="56" width="15" height="15" fill="@F@" stroke="@C@" stroke-width="@SW@"/>
  <path d="M 18 64 L 42 64 M 57 64 L 72 50" stroke="@C@" stroke-width="@SW@"/>
  <path d="M 57 64 L 72 64" stroke="@C@" stroke-width="@SWT@" stroke-dasharray="3 3"/>
  <path d="M 49 47 L 49 56 M 49 71 L 49 80" stroke="@C@" stroke-width="@SW@"/>
  {via(18, 64)}{via(72, 50)}{via(49, 44)}{via(49, 83)}''',

    # Reflex desync: a dilation ring with one arc dropped out, and the bolt
    # split into two halves that no longer meet.
    "reflex_jammer": f'''
  <path d="M 49 28 A 32 32 0 0 1 81 60" fill="none" stroke="@C@" stroke-width="@SW@"/>
  <path d="M 81 68 A 32 32 0 0 1 49 100" fill="none" stroke="@C@" stroke-width="@SWT@"
        stroke-dasharray="7 5"/>
  <path d="M 18 60 A 32 32 0 0 1 40 31" fill="none" stroke="@C@" stroke-width="@SW@"/>
  <path d="M 55 40 L 39 62 L 52 62" fill="none" stroke="@C@" stroke-width="@SW@"/>
  <path d="M 46 88 L 62 66 L 49 66" fill="none" stroke="@C@" stroke-width="@SW@"/>
  {via(49, 25)}{via(18, 63)}{via(81, 64)}''',

    # Kiroshi lens rewritten: angular optic, bracketed pupil, IFF tag struck out.
    "optic_overwrite": f'''
  <path d="M 17 60 L 32 45 L 67 45 L 82 60 L 67 75 L 32 75 Z"
        fill="none" stroke="@C@" stroke-width="@SW@"/>
  <rect x="43" y="53" width="13" height="14" fill="@F@" stroke="@C@" stroke-width="@SW@"/>
  <path d="M 37 52 L 37 68 M 62 52 L 62 68" stroke="@C@" stroke-width="@SW@"/>
  <path d="M 26 88 L 73 88 M 26 99 L 58 99" stroke="@C@" stroke-width="@SW@"/>
  <path d="M 20 102 L 79 84" stroke="@C@" stroke-width="@SWT@"/>
  {via(17, 60)}{via(82, 60)}''',

    # Phantom overlay: the real silhouette bracketed solid, the decoy dashed
    # and offset, with the seam running between them.
    "phantom_overlay": f'''
  <path d="M 27 32 L 27 96 M 27 32 L 41 32 M 27 96 L 41 96" stroke="@C@" stroke-width="@SW@"/>
  <path d="M 58 32 L 58 96 M 58 32 L 44 32 M 58 96 L 44 96" stroke="@C@" stroke-width="@SW@"/>
  <rect x="38" y="55" width="9" height="18" fill="@F@" stroke="@C@" stroke-width="@SW@"/>
  <path d="M 42.5 36 L 42.5 55 M 42.5 73 L 42.5 92" stroke="@C@" stroke-width="@SWT@"
        stroke-dasharray="3 3"/>
  <path d="M 76 40 L 76 88 M 76 40 L 88 40 M 76 88 L 88 88" stroke="@C@" stroke-width="@SWT@"
        stroke-dasharray="5 4"/>
  {via(27, 28)}{via(58, 28)}''',

    # Motor cortex inverted: the cortex contour with its command arrows
    # pointing back at each other.
    "motor_cortex": f'''
  <path d="M 20 72 L 20 46 L 34 32 L 65 32 L 79 46 L 79 72"
        fill="none" stroke="@C@" stroke-width="@SW@"/>
  <path d="M 20 72 L 34 86 L 65 86 L 79 72" fill="none" stroke="@C@" stroke-width="@SW@"/>
  <path d="M 32 52 L 52 52 M 32 52 L 39 45 M 32 52 L 39 59" fill="none"
        stroke="@C@" stroke-width="@SW@"/>
  <path d="M 67 66 L 47 66 M 67 66 L 60 59 M 67 66 L 60 73" fill="none"
        stroke="@C@" stroke-width="@SW@"/>
  <path d="M 49 94 L 49 100 M 34 94 L 34 100 M 65 94 L 65 100" stroke="@C@" stroke-width="@SWT@"/>
  {via(34, 103)}{via(49, 103)}{via(65, 103)}''',

    # Adrenaline overdose: injector driven into a heart trace that has already
    # gone into tachycardia.
    "adrenaline_overdose": f'''
  <path d="M 49 28 L 49 44" stroke="@C@" stroke-width="@SW@"/>
  <path d="M 38 34 L 60 34" stroke="@C@" stroke-width="@SW@"/>
  <rect x="40" y="44" width="19" height="18" fill="@F@" stroke="@C@" stroke-width="@SW@"/>
  <path d="M 40 62 L 59 62 L 49 76 Z" fill="none" stroke="@C@" stroke-width="@SW@"/>
  <path d="M 17 94 L 31 94 L 37 82 L 46 106 L 55 88 L 62 94 L 82 94"
        fill="none" stroke="@C@" stroke-width="@SW@"/>
  {via(17, 94)}{via(82, 94)}''',

    # Crypto-siphon: the eddie glyph bled off through a tapped conduit.
    "crypto_siphon": f'''
  <path d="M 66 40 L 36 40 L 28 48 L 28 58 L 36 66 L 62 66 L 70 74 L 70 84 L 62 92 L 32 92"
        fill="none" stroke="@C@" stroke-width="@SW@"/>
  <path d="M 49 30 L 49 40 M 49 92 L 49 102" stroke="@C@" stroke-width="@SW@"/>
  <path d="M 84 46 L 84 86" stroke="@C@" stroke-width="@SWT@" stroke-dasharray="4 4"/>
  <path d="M 84 88 L 79 80 M 84 88 L 89 80" stroke="@C@" stroke-width="@SWT@"/>
  {via(49, 27)}{via(49, 105)}{via(84, 43)}''',
}

# Vanilla stamps the same serial on every program card; these are per-hack so
# the shards read as a matched set rather than seven copies.
CARD_TMPL = '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128" width="128" height="128">
  <g transform="translate({cx},0)" stroke-linecap="butt" stroke-linejoin="miter"
     stroke-miterlimit="4" fill="none">
  {frame}
  <g clip-path="url(#panelclip)">
  <g transform="translate(49.5,{cy}) scale({ms}) translate(-49.5,-64)">
  {glow}
  {art}
  </g>
  </g>
  </g>
</svg>
'''

SCAN_TMPL = '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="64" height="64">
  <g transform="translate(32,32) scale({s}) translate({tx},{ty})"
     stroke-linecap="butt" stroke-linejoin="miter" stroke-miterlimit="4" fill="none">
  {glow}
  {art}
  </g>
</svg>
'''


def render(body: str, colour: str, sw: float, block: str = None) -> str:
    """@C@ stroke colour, @SW@/@SWT@ stroke widths, @F@ the fill of a solid block.

    The card wants a dark die with a bright contour, the way the shipped art
    draws it; the 64px scanner glyph wants the block filled solid or it reads
    as an empty rectangle at that size."""
    return (body.replace("@C@", colour)
                .replace("@F@", block if block is not None else colour)
                .replace("@SWT@", f"{sw * 0.7:.2f}")
                .replace("@SW@", f"{sw:.2f}"))


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "src")
    os.makedirs(out, exist_ok=True)

    def write(name, svg):
        io.open(os.path.join(out, name), "w", encoding="utf-8").write(svg)
        print(f"  wrote {name}")

    for name, body in PICTOGRAMS.items():
        # Card. Frame and glyph carry the SAME stroke weight in the shipped
        # art - roughly 4.5px on the 99px card. Anything finer turns to grey
        # mush at the ~40px the inventory grid actually renders. The motif sits
        # inside a scaled group, so its width is pre-divided by that scale.
        msw = 4.6 / MOTIF_SCALE
        write(name + ".svg", CARD_TMPL.format(
            cx=CARD_X,
            cy=f"{MOTIF_CY:.1f}",
            ms=f"{MOTIF_SCALE:.3f}",
            frame=frame(),
            glow=f'<g stroke-opacity="0.22" fill-opacity="0.22">'
                 f'{render(body, RIM, msw * 2.6)}</g>',
            art=render(body, RIM, msw),
        ))

        # Scanner. Scale the authoring box to 60px and fatten the strokes, or
        # 2px hairlines disappear entirely at 64x64.
        s = 60.0 / PBOX_H
        write(name + "_scanner.svg", SCAN_TMPL.format(
            s=f"{s:.4f}", tx=f"{-PCX}", ty=f"{-PCY}",
            glow=f'<g stroke-opacity="0.25" fill-opacity="0.25">'
                 f'{render(body, ART, 9.0)}</g>',
            art=render(body, ART, 4.2),
        ))


if __name__ == "__main__":
    main()
