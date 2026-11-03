#!/usr/bin/env python3
"""Writes the Silkworks page into scene.rml: a full-screen web app the
spider lives in, for publishing to the web. Replaces the page if it is
already there (artboard, view model, spider instance, converters), so
rerunning it after a change to this file is safe. Everything it writes has
an id with the 9: prefix.

The editor owns scene.rml: run this, check, and push. Edits made in the
editor to the page are lost if this runs again, so once the page is being
tuned in the editor, change it there instead.
"""

import re
import sys
from pathlib import Path
from xml.dom import minidom
from xml.sax.saxutils import quoteattr

SCENE = Path(__file__).resolve().parent.parent / "scene.rml"

# The spider's view model, and the ids in it this page writes.
SPIDER_VM = "0:2"
SPIDER_SM = "0:108"
SPIDER_BOARD = "0:236"
DESKTOP_SPIDER_INSTANCE = "0:46"
SP = {
    "originX": "0:34", "originY": "0:35", "agent": "7:7", "home": "8:2301",
    "pressLeft": "0:29", "pressRight": "0:30",
    "ink": "0:48", "leg": "0:49", "bodyTop": "0:50", "bodyBottom": "0:51", "marks": "0:52",
}
AGENT = {"idle": "7:2", "thinking": "7:3", "working": "7:4", "needsYou": "7:5", "done": "7:6"}
FONT = "0:54"
PAGE_SCRIPT = "9:1"
STAGE_SCRIPT = "9:2"

# Palettes, as in mac/Sources/Palette.swift (the Swift test checks those
# against the scene's colours; these are the same values).
PALETTES = [
    ("Grape", {"ink": "FF170D30", "leg": "FF4E3390", "bodyTop": "FFA27CF0", "bodyBottom": "FF32246F", "marks": "FFFFB8E6"}),
    ("Tangerine", {"ink": "FF2E0E08", "leg": "FFB8360E", "bodyTop": "FFFFC25C", "bodyBottom": "FFD93A1E", "marks": "FFFFF0B8"}),
    ("Lime", {"ink": "FF0B2410", "leg": "FF2F7E22", "bodyTop": "FFE6FF6E", "bodyBottom": "FF3DA62C", "marks": "FFFAFFD6"}),
    ("Bubblegum", {"ink": "FF2A0820", "leg": "FF9E1670", "bodyTop": "FFFF9FCC", "bodyBottom": "FFB81C78", "marks": "FFFFE6F3"}),
    ("Cyan", {"ink": "FF06172E", "leg": "FF1462A8", "bodyTop": "FF9EFBFF", "bodyBottom": "FF1C7FD8", "marks": "FFEFFFFF"}),
    ("Gold", {"ink": "FF2B1800", "leg": "FFA85F00", "bodyTop": "FFFFF08C", "bodyBottom": "FFE8870C", "marks": "FFFFF9DE"}),
    ("Black Widow", {"ink": "FF000000", "leg": "FF1D1A28", "bodyTop": "FF4C4560", "bodyBottom": "FF0E0C18", "marks": "FFFF3B30"}),
]

# The look.
PAGE_BG = "FFF4F1FA"
WHITE = "FFFFFFFF"
INK = "FF1B1530"
MUTED = "FF6E6787"
ACCENT = "FF6D4AFF"
LINE = "FFE7E1F3"
CLEAR = "00FFFFFF"
# Interactive fills: normal, hover, pressed.
PRIMARY = ("FF6D4AFF", "FF5A36F0", "FF4A28D6")
SECONDARY = ("FFF0EBFB", "FFE6DEFA", "FFDCD1F8")
CARD = ("FFFFFFFF", "FFFAF8FF", "FFF1ECFC")
ROW_BG = "FFFAF8FE"
SELECTED = "FFEDE7FF"
NOTE = "FFFFF3B0"
NOTE_STRIP = "FFFFE36E"
NOTE_W, NOTE_H, GRIP_H = 250, 170, 36  # stage.luau's
KNOB_ON = 23  # page.luau's: naps start on
TRACK_ON = "FF6D4AFF"

CATCHES = [
    ("Housefly", "2 min ago", "crunchy", "FF8A8F98"),
    ("Mosquito", "6 min ago", "zippy", "FFC97B5A"),
    ("Fruit fly", "11 min ago", "sweet", "FFE0A63A"),
    ("Moth", "18 min ago", "dusty", "FFB9A88E"),
    ("Gnat", "25 min ago", "tiny", "FF6F7A5A"),
    ("Midge", "31 min ago", "fizzy", "FF7DA7B8"),
    ("Crane fly", "40 min ago", "leggy", "FFA88F6C"),
    ("Aphid", "52 min ago", "green", "FF79B85A"),
    ("Lacewing", "1 h ago", "delicate", "FF8FCB9B"),
    ("Hoverfly", "1 h ago", "stripy", "FFE8B23A"),
    ("Mayfly", "2 h ago", "fleeting", "FFC9B8A0"),
    ("Thrips", "2 h ago", "speck", "FF5E5A6E"),
    ("Blowfly", "3 h ago", "shiny", "FF3E8E7E"),
    ("Sandfly", "3 h ago", "gritty", "FFD2B48C"),
    ("Leafhopper", "4 h ago", "bouncy", "FF6FBF73"),
    ("Firefly", "last night", "glowing", "FFF2D43A"),
]
MODES = [("Idle", "idle"), ("Thinking", "thinking"), ("Working", "working"), ("Needs you", "needsYou"), ("Done", "done")]

_next = [2]


def nid():
    _next[0] += 1
    return f"9:{_next[0]}"


def attrs(**kw):
    out = []
    for k, v in kw.items():
        if v is None:
            continue
        k = k.rstrip("_")
        out.append(f"{k}={quoteattr(str(v))}")
    return " ".join(out)


class Page:
    def __init__(self):
        self.vm = nid()
        self.instance = nid()
        self.spider_prop = nid()
        self.spider_instance = nid()
        self.props = []  # (xml, instance xml)
        self.prop_ids = {}
        self.listeners = []
        self.converters = []
        self.physics = nid()

    # View model -------------------------------------------------------------

    def prop(self, kind, name, value=None):
        pid = nid()
        self.prop_ids[name] = pid
        decl = f'<ViewModelProperty{kind} name="{name}" id="{pid}"/>'
        if kind == "Trigger":
            inst = f'<ViewModelInstanceTrigger viewModelPropertyId="{pid}" id="{nid()}"/>'
        else:
            val = "" if value is None else f'propertyValue={quoteattr(str(value))} '
            inst = f"<ViewModelInstance{kind} {val}viewModelPropertyId=\"{pid}\" id=\"{nid()}\"/>"
        self.props.append((decl, inst))
        return pid

    def path(self, name):
        return f"{self.vm}-{self.prop_ids[name]}"

    def spider_path(self, name):
        return f"{self.vm}-{self.spider_prop}-{SP[name]}"

    # Listeners ----------------------------------------------------------------

    def set_color(self, path, value):
        return (f'<ListenerViewModelChange id="{nid()}"><BindablePropertyColor propertyValue="{value}" id="{nid()}">'
                f'<DataBindContext sourcePathIds="{path}" propertyKey="638" direction="true" id="{nid()}"/>'
                f"</BindablePropertyColor></ListenerViewModelChange>")

    def set_string(self, path, value):
        return (f'<ListenerViewModelChange id="{nid()}"><BindablePropertyString propertyValue="{value}" id="{nid()}">'
                f'<DataBindContext sourcePathIds="{path}" propertyKey="635" direction="true" id="{nid()}"/>'
                f"</BindablePropertyString></ListenerViewModelChange>")

    def set_bool(self, path, value):
        v = ' propertyValue="true"' if value else ""
        return (f'<ListenerViewModelChange id="{nid()}"><BindablePropertyBoolean{v} id="{nid()}">'
                f'<DataBindContext sourcePathIds="{path}" propertyKey="634" direction="true" id="{nid()}"/>'
                f"</BindablePropertyBoolean></ListenerViewModelChange>")

    def set_enum(self, path, value):
        return (f'<ListenerViewModelChange id="{nid()}"><BindablePropertyEnum propertyValue="{value}" id="{nid()}">'
                f'<DataBindContext sourcePathIds="{path}" propertyKey="637" direction="true" id="{nid()}"/>'
                f"</BindablePropertyEnum></ListenerViewModelChange>")

    def fire(self, path):
        return (f'<ListenerViewModelChange id="{nid()}"><BindablePropertyTrigger propertyValue="1" id="{nid()}">'
                f'<DataBindContext sourcePathIds="{path}" propertyKey="686" direction="true" id="{nid()}"/>'
                f"</BindablePropertyTrigger></ListenerViewModelChange>")

    def listen(self, target, kind, name, *actions):
        t = "" if kind == "enter" else f' listenerTypeValue="{kind}"'
        self.listeners.append(
            f'<StateMachineListenerSingle{t} targetId="{target}" name={quoteattr(name)} id="{nid()}">'
            + "".join(actions) + "</StateMachineListenerSingle>")

    def interactive(self, target, name, colors=None, color_prop=None, click=()):
        """Pointer cursor on hover; hover and press colours if given; click actions."""
        cursor = self.path("cursor")
        enter, leave, down, up = [self.set_string(cursor, "pointer")], [self.set_string(cursor, "arrow")], [], []
        if colors:
            p = self.path(color_prop)
            enter.append(self.set_color(p, colors[1]))
            leave.append(self.set_color(p, colors[0]))
            down.append(self.set_color(p, colors[2]))
            up.append(self.set_color(p, colors[1]))
        self.listen(target, "enter", f"{name} enter", *enter)
        self.listen(target, "exit", f"{name} exit", *leave)
        if down:
            self.listen(target, "down", f"{name} down", *down)
            self.listen(target, "up", f"{name} up", *up)
        if click:
            self.listen(target, "click", f"{name} click", *click)


P = Page()


# Markup helpers -------------------------------------------------------------

def style(children="", **kw):
    sid = nid()
    units = {}
    for k in list(kw):
        if k.startswith(("padding", "gap", "positionLeft", "positionRight", "positionTop", "positionBottom")) and not k.endswith("UnitsValue"):
            units[k + "UnitsValue"] = "points"
    kw.update({k: v for k, v in units.items() if k not in kw})
    if children:
        return sid, f'<LayoutComponentStyle {attrs(**kw)} name="Style" id="{sid}">{children}</LayoutComponentStyle>'
    return sid, f'<LayoutComponentStyle {attrs(**kw)} name="Style" id="{sid}"/>'


def fill(color, bind=None):
    b = f'<DataBindContext sourcePathIds="{bind}" propertyKey="37" id="{nid()}"/>' if bind else ""
    return f'<Fill name="Fill" id="{nid()}"><SolidColor colorValue="{color}" name="Color" id="{nid()}">{b}</SolidColor></Fill>'


def stroke(color, thickness=1):
    return (f'<Stroke thickness="{thickness}" name="Border" id="{nid()}"><SolidColor colorValue="{color}" name="Color" id="{nid()}"/></Stroke>')


def box(name, children, width=100, height=100, paint="", clip=False, style_children="", **style_kw):
    bid = nid()
    sid, s = style(style_children, **style_kw)
    c = ' clip="true"' if clip else ""
    return bid, (f'<LayoutComponent{c} width="{width}" height="{height}" styleId="{sid}" name={quoteattr(name)} id="{bid}">'
                 + s + paint + "".join(children) + "</LayoutComponent>")


WEIGHTS = {400: "Regular", 500: "Medium", 600: "SemiBold", 700: "Bold", 800: "ExtraBold"}


def text(value, size, color=INK, weight=400, width="hug", bind=None, converter=None, name=None, participant=True):
    tid, sid = nid(), nid()
    part = (f'<LayoutParticipant layoutWidthScaleType="{width}" layoutHeightScaleType="hug" name="Layout" id="{nid()}"/>'
            if participant else "")
    b = ""
    if bind:
        conv = f' converterId="{converter}"' if converter else ""
        b = f'<DataBindContext sourcePathIds="{bind}" propertyKey="268"{conv} id="{nid()}"/>'
    sizing = ' wrapValue="wrap"' if width == "fill" else ""
    if width == "fill":
        part = part.replace(" name=\"Layout\"", " maxWidth=\"680\" maxWidthUnitsValue=\"points\" name=\"Layout\"", 1)
    return (f'<Text{sizing} name={quoteattr(name or value[:24])} id="{tid}">' + part
            + f'<TextStylePaint fontSize="{size}" fontAssetId="{FONT}" familyName="Inter" styleName="{WEIGHTS[weight]}" name="Style" id="{sid}">'
            + fill(color)
            + f'<TextStyleAxis tag="2003265652" axisValue="{weight}" name="Weight" id="{nid()}"/>'
            + "</TextStylePaint>"
            + f'<TextValueRun styleId="{sid}" text={quoteattr(value)} name="Run" id="{nid()}">{b}</TextValueRun>'
            + "</Text>")


def dot(size, color, name="Dot"):
    return (f'<Shape name="{name}" id="{nid()}">'
            f'<LayoutParticipant layoutWidthScaleType="fixed" layoutHeightScaleType="fixed" width="{size}" height="{size}" name="Layout" id="{nid()}"/>'
            f'<Ellipse width="{size}" height="{size}" name="Path" id="{nid()}"/>' + fill(color) + "</Shape>")


# The page -------------------------------------------------------------------

def button(label, colors, text_color, prop, click):
    P.prop("Color", prop, colors[0])
    bid, xml = box(label, [text(label, 15, text_color, 600)], paint=fill(colors[0], P.path(prop)),
                   layoutWidthScaleType="hug", layoutHeightScaleType="hug", flexDirectionValue="row",
                   layoutAlignmentType="center", paddingLeft=20, paddingRight=20, paddingTop=12, paddingBottom=12,
                   cornerRadiusTL=12)
    P.interactive(bid, label, colors, prop, click)
    return xml


def logo():
    rings = "".join(f'<Ellipse width="{d}" height="{d}" name="Ring" id="{nid()}"/>' for d in (18, 10))
    spokes = "".join(
        f'<PointsPath isClosed="false" name="Spoke" id="{nid()}">'
        f'<StraightVertex x="{x1}" y="{y1}" id="{nid()}"/><StraightVertex x="{x2}" y="{y2}" id="{nid()}"/></PointsPath>'
        for x1, y1, x2, y2 in ((-9, 0, 9, 0), (0, -9, 0, 9), (-6.4, -6.4, 6.4, 6.4), (-6.4, 6.4, 6.4, -6.4)))
    web = (f'<Shape name="Web" id="{nid()}">'
           f'<LayoutParticipant layoutWidthScaleType="fixed" layoutHeightScaleType="fixed" width="18" height="18" name="Layout" id="{nid()}"/>'
           + rings + spokes + f'<Stroke thickness="1.6" cap="round" name="Line" id="{nid()}"><SolidColor colorValue="{WHITE}" name="Color" id="{nid()}"/></Stroke></Shape>')
    _, mark = box("Logo", [web], width=32, height=32, paint=fill(ACCENT), layoutWidthScaleType="fixed",
                  layoutHeightScaleType="fixed", flexDirectionValue="row", layoutAlignmentType="center", cornerRadiusTL=10)
    _, brand = box("Brand", [mark, text("Silkworks", 19, INK, 700)], layoutWidthScaleType="hug", layoutHeightScaleType="hug",
                   flexDirectionValue="row", layoutAlignmentType="centerLeft", gapHorizontal=10)
    return brand


def top_bar():
    # The brand and what the page is, nothing that looks clickable and is
    # not. The right end stays clear for the spider's web in the corner.
    tagline = text("A spider that lives on your pointer", 14, MUTED, 500)
    _, left = box("Left", [logo(), tagline], layoutWidthScaleType="hug", layoutHeightScaleType="hug",
                  flexDirectionValue="row", layoutAlignmentType="centerLeft", gapHorizontal=20)
    _, bar = box("Top Bar", [left], height=68, paint=fill(WHITE) + stroke(LINE),
                 layoutWidthScaleType="fill", layoutHeightScaleType="fixed", flexDirectionValue="row",
                 layoutAlignmentType="centerLeft", paddingLeft=32, paddingRight=190)
    return bar


def hero():
    title = text("Meet Silk.", 44, INK, 800)
    sub = text("Silk follows your pointer. Click and a front leg presses for you, scroll the list and it drags "
               "the page along, keep still and it finds something to do. Drag the yellow note and it hangs on.",
               16, MUTED, 400, width="fill", name="Intro")
    buttons = [
        button("Send Silk home", PRIMARY, WHITE, "homeButton", [P.set_bool(P.spider_path("home"), True)]),
        button("Call Silk back", SECONDARY, "FF3A2C7A", "backButton", [P.set_bool(P.spider_path("home"), False)]),
    ]
    _, row = box("Buttons", buttons, layoutWidthScaleType="hug", layoutHeightScaleType="hug", flexDirectionValue="row", gapHorizontal=12)
    _, card = box("Hero", [title, sub, row], paint=fill(WHITE) + stroke(LINE), layoutWidthScaleType="fill",
                  layoutHeightScaleType="hug", flexDirectionValue="column", paddingLeft=32, paddingRight=32,
                  paddingTop=28, paddingBottom=28, gapVertical=14, cornerRadiusTL=20)
    return card


def stats():
    as_text = nid()
    P.converters.append(f'<DataConverterToString decimals="0" round="true" name="Whole number" id="{as_text}"/>')
    cards = []
    for label, prop, start, trigger, hint in [
        ("Flies caught", "flies", 12, "catchFly", "Click to catch one"),
        ("Webs spun", "webs", 4, "spinWeb", "Click to spin one"),
        ("Pats", "pats", 0, "pat", "Click to pat Silk"),
    ]:
        P.prop("Number", prop, start)
        P.prop("Trigger", trigger)
        color = f"{prop}Card"
        P.prop("Color", color, CARD[0])
        bid, card = box(label, [
            text(label, 13, MUTED, 500),
            text(str(start), 36, INK, 800, bind=P.path(prop), converter=as_text, name=f"{label} count"),
            text(hint, 12, ACCENT, 600),
        ], paint=fill(CARD[0], P.path(color)) + stroke(LINE), layoutWidthScaleType="fill", layoutHeightScaleType="hug",
            flexDirectionValue="column", paddingLeft=20, paddingRight=20, paddingTop=18, paddingBottom=18, gapVertical=4,
            cornerRadiusTL=16)
        P.interactive(bid, label, CARD, color, [P.fire(P.path(trigger))])
        cards.append(card)
    _, row = box("Stats", cards, layoutWidthScaleType="fill", layoutHeightScaleType="hug", flexDirectionValue="row", gapHorizontal=20)
    return row


def feed():
    rows = []
    for i, (name, when, taste, color) in enumerate(CATCHES):
        _, left = box("Left", [dot(12, color), text(name, 15, INK, 600), text(taste, 13, MUTED)],
                      layoutWidthScaleType="hug", layoutHeightScaleType="hug", flexDirectionValue="row",
                      layoutAlignmentType="centerLeft", gapHorizontal=12)
        _, row = box(name, [left, text(when, 13, MUTED)], height=50, paint=fill(ROW_BG),
                       layoutWidthScaleType="fill", layoutHeightScaleType="fixed", flexDirectionValue="row",
                       layoutAlignmentType="spaceBetweenCenter", paddingLeft=14, paddingRight=14, cornerRadiusTL=12)
        rows.append(row)
    scroll_id = nid()
    # The list's offset, written back for page.luau: the spider's feet
    # follow how far the list really moved, whatever moved it.
    P.prop("Number", "listScroll", 0)
    offset = f'<DataBindContext sourcePathIds="{P.path("listScroll")}" propertyKey="760" direction="true" id="{nid()}"/>'
    content_id, content = box("Content", rows + [
        f'<ScrollConstraint directionValue="vertical" physicsId="{P.physics}" name="Scroll" id="{scroll_id}">{offset}</ScrollConstraint>'],
        layoutWidthScaleType="fill", layoutHeightScaleType="hug", flexDirectionValue="column", gapVertical=4)
    _, viewport = box("Viewport", [content], clip=True, layoutWidthScaleType="fill", layoutHeightScaleType="fill",
                      flexDirectionValue="column")
    _, thumb = box("Thumb", [f'<ScrollBarConstraint scrollConstraintId="{scroll_id}" directionValue="vertical" name="Bar" id="{nid()}"/>'],
                   width=6, height=60, paint=fill("FFCFC4EE"), layoutWidthScaleType="fixed", layoutHeightScaleType="fixed",
                   cornerRadiusTL=3)
    _, track = box("Track", [thumb], width=6, height=100, paint=fill("FFF1EDF9"), layoutWidthScaleType="fixed",
                   layoutHeightScaleType="fill", cornerRadiusTL=3)
    _, body = box("List", [viewport, track], layoutWidthScaleType="fill", layoutHeightScaleType="fill",
                  flexDirectionValue="row", gapHorizontal=10)
    _, head = box("Header", [text("Recent catches", 17, INK, 700), text("Scroll or drag it", 13, MUTED)],
                  layoutWidthScaleType="fill", layoutHeightScaleType="hug", flexDirectionValue="row",
                  layoutAlignmentType="spaceBetweenCenter")
    _, card = box("Feed", [head, body], paint=fill(WHITE) + stroke(LINE), layoutWidthScaleType="fill",
                  layoutHeightScaleType="fill", flexDirectionValue="column", paddingLeft=20, paddingRight=14,
                  paddingTop=18, paddingBottom=14, gapVertical=12, cornerRadiusTL=16)
    return card


def card(name, children, gap=10, **kw):
    _, xml = box(name, children, paint=fill(WHITE) + stroke(LINE), layoutWidthScaleType="fill",
                 layoutHeightScaleType="hug", flexDirectionValue="column", paddingLeft=20, paddingRight=20,
                 paddingTop=18, paddingBottom=18, gapVertical=gap, cornerRadiusTL=16, **kw)
    return xml


def mood():
    buttons = []
    props = []
    for label, key in MODES:
        prop = f"mode{key[0].upper()}{key[1:]}"
        P.prop("Color", prop, SELECTED if key == "idle" else WHITE)
        props.append((key, prop))
    for label, key in MODES:
        prop = f"mode{key[0].upper()}{key[1:]}"
        bid, b = box(label, [text(label, 14, INK, 600)], height=40,
                     paint=fill(SELECTED if key == "idle" else WHITE, P.path(prop)) + stroke(LINE),
                     layoutWidthScaleType="fill", layoutHeightScaleType="fixed", flexDirectionValue="row",
                     layoutAlignmentType="centerLeft", paddingLeft=14, cornerRadiusTL=10)
        P.interactive(bid, label, click=[P.set_enum(P.spider_path("agent"), AGENT[key])]
                      + [P.set_color(P.path(p), SELECTED if k == key else WHITE) for k, p in props])
        buttons.append(b)
    return card("Mood", [text("Silk's mood", 17, INK, 700),
                         text("What a coding agent would show", 13, MUTED)] + buttons, gap=8)


def colours():
    swatches = []
    for name, pal in PALETTES:
        bid, s = box(name, [], width=30, height=30, paint=fill("FF" + pal["bodyTop"][2:]) + stroke("FF" + pal["leg"][2:], 3),
                     layoutWidthScaleType="fixed", layoutHeightScaleType="fixed", cornerRadiusTL=15)
        P.interactive(bid, name, click=[P.set_color(P.spider_path(slot), v) for slot, v in pal.items()])
        swatches.append(s)
    _, row = box("Swatches", swatches, layoutWidthScaleType="fill", layoutHeightScaleType="hug", flexDirectionValue="row",
                 flexWrapValue="wrap", gapHorizontal=6, gapVertical=6)
    return card("Colours", [text("Colours", 17, INK, 700), row])


def naps():
    P.prop("Number", "napsKnob", KNOB_ON)
    P.prop("Color", "napsTrack", TRACK_ON)
    P.prop("Trigger", "toggleNaps")
    smooth = nid()
    P.converters.append(f'<DataConverterInterpolator interpolationType="cubic" duration="0.18" name="Slide" id="{smooth}"/>')
    # The knob slides by its left inset, which lives on its style.
    slide = f'<DataBindContext sourcePathIds="{P.path("napsKnob")}" propertyKey="516" converterId="{smooth}" id="{nid()}"/>'
    _, knob = box("Knob", [], width=20, height=20, paint=fill(WHITE), style_children=slide,
                  positionTypeValue="absolute", positionLeft=KNOB_ON, positionTop=3, layoutWidthScaleType="fixed",
                  layoutHeightScaleType="fixed", cornerRadiusTL=10)
    bid, track = box("Switch", [knob], width=46, height=26, paint=fill(TRACK_ON, P.path("napsTrack")),
                     layoutWidthScaleType="fixed", layoutHeightScaleType="fixed", cornerRadiusTL=13)
    P.interactive(bid, "Naps switch", click=[P.fire(P.path("toggleNaps"))])
    _, words = box("Words", [text("Naps", 17, INK, 700), text("Silk dozes when you stop", 13, MUTED)],
                   layoutWidthScaleType="hug", layoutHeightScaleType="hug", flexDirectionValue="column", gapVertical=2)
    _, row = box("Row", [words, track], layoutWidthScaleType="fill", layoutHeightScaleType="hug", flexDirectionValue="row",
                 layoutAlignmentType="spaceBetweenCenter")
    return card("Naps", [row])


def note():
    # Hand placed, not laid out: the script moves it by its top left.
    def rect(name, x, y, w, h, color, r):
        return (f'<Shape x="{x + w / 2}" y="{y + h / 2}" name="{name}" id="{nid()}">'
                f'<Rectangle cornerRadiusTL="{r}" width="{w}" height="{h}" name="Path" id="{nid()}"/>' + fill(color) + "</Shape>")

    def label(value, x, y, size, weight, color, width=None):
        tid, sid = nid(), nid()
        sizing = f' sizingValue="fixed" width="{width}"' if width else ""
        return (f'<Text x="{x}" y="{y}"{sizing} name={quoteattr(value[:24])} id="{tid}">'
                f'<TextStylePaint fontSize="{size}" fontAssetId="{FONT}" familyName="Inter" styleName="{WEIGHTS[weight]}" name="Style" id="{sid}">'
                + fill(color) + f'<TextStyleAxis tag="2003265652" axisValue="{weight}" name="Weight" id="{nid()}"/></TextStylePaint>'
                f'<TextValueRun styleId="{sid}" text={quoteattr(value)} name="Run" id="{nid()}"/></Text>')

    P.prop("Number", "noteX", 1150)
    P.prop("Number", "noteY", 690)
    grip_id = nid()
    grip = (f'<Shape x="{NOTE_W / 2}" y="{GRIP_H / 2}" name="Strip" id="{grip_id}">'
            f'<Rectangle cornerRadiusTL="14" cornerRadiusTR="14" linkCornerRadius="false" width="{NOTE_W}" height="{GRIP_H}" name="Path" id="{nid()}"/>'
            + fill(NOTE_STRIP) + "</Shape>")
    P.interactive(grip_id, "Note strip")
    nid_ = nid()
    return (f'<Node name="Note (code)" id="{nid_}">'
            + label("Drag me", 16, 9, 14, 700, "FF5C4300")
            + label("Grab the strip and shake it. Silk holds on, then hops off when you let go.", 16, GRIP_H + 14, 14, 500, "FF5C4300", NOTE_W - 32)
            + grip
            + rect("Paper", 0, 0, NOTE_W, NOTE_H, NOTE, 14)
            + rect("Shadow", 4, 8, NOTE_W, NOTE_H, "22000000", 14)
            + f'<DataBindContext sourcePathIds="{P.path("noteX")}" propertyKey="13" id="{nid()}"/>'
            + f'<DataBindContext sourcePathIds="{P.path("noteY")}" propertyKey="14" id="{nid()}"/>'
            + "</Node>")


def build():
    P.prop("String", "cursor", "arrow")
    main = box("Main", [hero(), stats(), feed()], layoutWidthScaleType="fill", layoutHeightScaleType="fill",
               flexDirectionValue="column", gapVertical=20)[1]
    side = box("Side", [mood(), colours(), naps()], width=300, layoutWidthScaleType="fixed", layoutHeightScaleType="hug",
               flexDirectionValue="column", gapVertical=20)[1]
    body = box("Body", [main, side], layoutWidthScaleType="fill", layoutHeightScaleType="fill", flexDirectionValue="row",
               paddingLeft=28, paddingRight=28, paddingTop=24, paddingBottom=24, gapHorizontal=24)[1]
    page = box("Page", [top_bar(), body], width=1440, height=900, paint=fill(PAGE_BG), layoutWidthScaleType="fill",
               layoutHeightScaleType="fill", flexDirectionValue="column")[1]
    the_note = note()

    # The host: on top of the page and as big as it, transparent, so the
    # spider's presses land anywhere and the script sees every move.
    host_id = nid()
    # Pinned to all four edges an absolute box keeps its authored size; a
    # percentage size follows the page.
    sid, s = style(positionTypeValue="absolute", positionLeft=0, positionTop=0, layoutWidthScaleType="fixed",
                   layoutHeightScaleType="fixed", widthUnitsValue="percent", heightUnitsValue="percent")
    host = (f'<LayoutComponent width="100" height="100" styleId="{sid}" name="Host (code)" id="{host_id}">' + s
            + fill("00000000") + f'<ScriptedLayout scriptAssetId="{PAGE_SCRIPT}" name="Page Script" id="{nid()}"/></LayoutComponent>')
    presses = "".join(
        f'<StateMachineListener targetId="{host_id}" name="{name}" id="{nid()}">'
        f'<ListenerInputTypePointerButton{button} listenerTypeValue="down" id="{nid()}"/>'
        + P.fire(P.spider_path(trigger)) + "</StateMachineListener>"
        for name, button, trigger in [("Press Left", "", "pressLeft"), ("Press Right", ' pointerButtonValue="secondary"', "pressRight")])

    spider = (f'<NestedArtboard artboardId="{SPIDER_BOARD}" dataBindPathIds="{P.vm}-{P.spider_prop}" isStateful="true" name="Spider" id="{nid()}">'
              f'<NestedStateMachine animationId="{SPIDER_SM}" name="Spider" id="{nid()}"/>'
              f'<DataBindContext sourcePathIds="{P.spider_path("originX")}" propertyKey="13" id="{nid()}"/>'
              f'<DataBindContext sourcePathIds="{P.spider_path("originY")}" propertyKey="14" id="{nid()}"/>'
              "</NestedArtboard>")

    sm_id, layer = nid(), nid()
    sm = (f'<StateMachine name="Silkworks" id="{sm_id}">' + presses + "".join(P.listeners)
          + f'<StateMachineLayer name="Layer" id="{layer}"><AnyState x="200" id="{nid()}"/><ExitState x="400" id="{nid()}"/>'
          f'<EntryState id="{nid()}"/></StateMachineLayer></StateMachine>')
    art_style = nid()
    artboard = (f'<Artboard defaultStateMachineId="{sm_id}" viewModelId="{P.vm}" clip="true" width="1440" height="900" '
                f'styleId="{art_style}" y="800" name="Silkworks" id="{nid()}">'
                f'<LayoutComponentStyle flexDirectionValue="column" name="Artboard Style" id="{art_style}"/>'
                + spider + the_note + host + page + sm + "</Artboard>")
    return artboard


def spider_instance(scene):
    """A copy of Desktop's spider instance, with its own ids, for the page."""
    m = re.search(r'\n( *)<ViewModelInstance exports="true" name="Desktop Spider" id="%s">.*?</ViewModelInstance>' % DESKTOP_SPIDER_INSTANCE, scene, re.S)
    block = m.group(0).strip("\n")
    block = block.replace('name="Desktop Spider" id="%s"' % DESKTOP_SPIDER_INSTANCE, f'name="Page Spider" id="{P.spider_instance}"', 1)
    return re.sub(r' id="\d+:\d+"(?=/>)', lambda _: f' id="{nid()}"', block)


def view_model(scene):
    decls = "".join(d for d, _ in P.props)
    insts = "".join(i for _, i in P.props)
    return (f'<ViewModel defaultInstanceId="{P.instance}" name="Page" id="{P.vm}">'
            f'<ViewModelPropertyViewModel viewModelReferenceId="{SPIDER_VM}" name="spider" id="{P.spider_prop}"/>' + decls
            + f'<ViewModelInstance exports="true" name="Instance" id="{P.instance}">'
            + f'<ViewModelInstanceViewModel propertyValue="{P.spider_instance}" viewModelPropertyId="{P.spider_prop}" id="{nid()}"/>'
            + insts + "</ViewModelInstance></ViewModel>")


def pretty(xml, depth):
    """One element, indented four spaces a level, starting `depth` levels in."""
    out = minidom.parseString(xml).documentElement.toprettyxml(indent="    ")
    pad = "    " * depth
    return "\n".join(pad + line if i else line for i, line in enumerate(out.strip().split("\n")))


def strip_old(scene):
    """Removes a page this wrote before: every element with a 9: id outside the scripts."""
    scene = re.sub(r'\n *<Artboard [^>]*name="Silkworks".*?</Artboard>', "", scene, flags=re.S)
    scene = re.sub(r'\n *<ViewModel [^>]*name="Page" id="9:\d+">.*?</ViewModel>', "", scene, flags=re.S)
    scene = re.sub(r'\n *<ViewModelInstance exports="true" name="Page Spider" id="9:\d+">.*?</ViewModelInstance>', "", scene, flags=re.S)
    scene = re.sub(r'\n *<(DataConverter\w*|ElasticScrollPhysics) [^>]*id="9:\d+"/>', "", scene)
    return scene


def main():
    scene = strip_old(SCENE.read_text())
    artboard = build()
    physics = f'<ElasticScrollPhysics friction="3" speedMultiplier="1.1" elasticFactor="0.7" name="Catches Physics" id="{P.physics}"/>'
    roots = P.converters + [physics]
    # The scripts, once.
    if 'file="stage.luau"' not in scene:
        roots += [f'<ScriptAsset file="stage.luau" isModule="true" compilationOrder="10" name="stage" id="{STAGE_SCRIPT}"/>',
                  f'<ScriptAsset file="page.luau" dependencyIds="{STAGE_SCRIPT}" compilationOrder="11" scriptProtocolValue="layout" name="page" id="{PAGE_SCRIPT}"/>']
    # The page's spider instance goes into the Spider view model, beside
    # Desktop's.
    inst = spider_instance(scene)
    anchor = re.search(r'( *)<ViewModelInstance exports="true" name="Desktop Spider" id="%s">' % DESKTOP_SPIDER_INSTANCE, scene)
    scene = scene[:anchor.start()] + anchor.group(1) + pretty(inst.strip(), 2) + "\n" + scene[anchor.start():]
    # The artboard after the others, the view model and roots before </Rive>.
    end = scene.rindex("</Rive>")
    added = [artboard, view_model(scene)] + roots
    scene = scene[:end] + "".join("    " + pretty(x, 1) + "\n" for x in added) + scene[end:]
    SCENE.write_text(scene)
    print(f"wrote the Silkworks page, ids up to 9:{_next[0]}")


if __name__ == "__main__":
    sys.exit(main())
