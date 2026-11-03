#!/usr/bin/env python3
"""Checks the scene's structure:

    python3 scene_test.py

Each leg draws its two colour strokes over both of its outlines, so the
upper and lower segment merge at the knee and the outline only shows round
the leg as a whole. Within a leg that needs draw rules: tree order alone
paints the upper segment, outline and all, over the lower one.
"""

import math
import os
import re
import sys
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))


def rig():
    """The leg table and view size the scripts use, from rig.luau."""
    src = open(os.path.join(HERE, "rig.luau")).read()
    legs = [
        {k: float(v) for k, v in re.findall(r"(\w+) = (-?[\d.]+)", line)}
        for line in src.splitlines()
        if "name =" in line
    ]
    return legs, float(re.search(r"viewSize = ([\d.]+)", src).group(1))


def defaults(root, model):
    """A view model's default instance values, by property name."""
    vm = next(v for v in root.iter("ViewModel") if v.get("name") == model)
    names = {p.get("id"): p.get("name") for p in vm if p.tag.startswith("ViewModelProperty")}
    inst = next(i for i in vm.iter("ViewModelInstance") if i.get("id") == vm.get("defaultInstanceId"))
    return {names[v.get("viewModelPropertyId")]: v.get("propertyValue", "0") for v in inst}


def strokes(shape):
    return {s.get("name") for s in shape.findall("Stroke")}


def silkworks(root, swift):
    """The Silkworks page: the published artboard, a web app the spider
    lives in."""
    failures = []
    page = next((a for a in root.iter("Artboard") if a.get("name") == "Silkworks"), None)
    if page is None:
        return ["no Silkworks artboard"]
    # It is what a publish shows.
    yaml = open(os.path.join(HERE, "rive.yaml")).read()
    if not re.search(r'^main: "?Silkworks"?$', yaml, re.M):
        failures.append("Silkworks is not the main artboard, so a publish shows something else")
    names = {p.get("id"): p.get("name") for p in root.iter() if p.tag.startswith("ViewModelProperty")}

    def writes(listener):
        """What a listener sets: (property name, value) pairs."""
        out = []
        for b in listener.iter():
            if b.tag.startswith("BindableProperty"):
                ctx = b.find("DataBindContext")
                out.append((names.get(ctx.get("sourcePathIds").split("-")[-1]), b.get("propertyValue")))
        return out

    sm = page.find("StateMachine")
    listeners = list(sm.iter("StateMachineListenerSingle"))
    # The spider is on top of everything on the page: the first drawable.
    first = next(c for c in page if c.tag not in ("LayoutComponentStyle",))
    if first.tag != "NestedArtboard" or first.get("name") != "Spider":
        failures.append("the spider is not drawn on top of the page")
    # The host covers the page at any size: an absolute box pinned by all
    # four insets keeps its authored size and the script never hears the
    # page resize, so it is sized in percent.
    host = next(c for c in page.iter("LayoutComponent") if c.get("name") == "Host (code)")
    hs = host.find("LayoutComponentStyle")
    if (hs.get("positionTypeValue"), hs.get("widthUnitsValue"), hs.get("heightUnitsValue"), host.get("width"), host.get("height")) != (
            "absolute", "percent", "percent", "100", "100"):
        failures.append("the page's host is not sized to the whole page")
    # Every control shows the pointing hand while hovered and the arrow after.
    by_target = {}
    for l in listeners:
        by_target.setdefault(l.get("targetId"), {})[l.get("listenerTypeValue", "enter")] = writes(l)
    if len(by_target) < 15:
        failures.append(f"only {len(by_target)} controls on the page")
    node_names = {n.get("id"): n.get("name") for n in page.iter() if n.get("id")}
    for target, kinds in by_target.items():
        if ("cursor", "pointer") not in kinds.get("enter", []) or ("cursor", "arrow") not in kinds.get("exit", []):
            failures.append(f"control {target} does not show the hand while hovered")
        # Nothing looks clickable that does nothing: every hand clicks, but
        # the note's strip, which page.luau drags.
        if "click" not in kinds and node_names.get(target) != "Strip":
            failures.append(f"{node_names.get(target)} shows the hand but does nothing")
    clicks = [writes(l) for l in listeners if l.get("listenerTypeValue") == "click"]
    # Each mood button sets its mode, and only its own button is selected.
    enum_values = {v.get("id"): v.get("key") for v in root.iter("DataEnumValue")}
    modes = sorted(enum_values.get(v) for c in clicks for n, v in c if n == "agent")
    if modes != sorted(["idle", "thinking", "working", "needsYou", "done"]):
        failures.append(f"the mood buttons set {modes}")
    for c in clicks:
        mode = [enum_values.get(v) for n, v in c if n == "agent"]
        if mode:
            selected = [n for n, v in c if n.startswith("mode") and v != "FFFFFFFF"]
            if selected != ["mode" + mode[0][0].upper() + mode[0][1:]]:
                failures.append(f"choosing {mode[0]} selects {selected}")
    # Each swatch sets every colour slot to one of the app's palettes.
    palettes = [
        {k: v.upper() for k, v in re.findall(r'"(\w+)": 0x([0-9A-Fa-f]{8})', body)}
        for body in re.findall(r'Palette\(name: "[^"]*", colors: \[(.*?)\]', swift, re.S)
    ]
    swatches = [dict(c) for c in clicks if any(n == "bodyTop" for n, _ in c)]
    if len(swatches) != len(palettes) or any(s not in palettes for s in swatches):
        failures.append("the colour swatches are not the app's palettes")
    # Home and back.
    homes = sorted(v or "false" for c in clicks for n, v in c if n == "home")
    if homes != ["false", "true"]:
        failures.append(f"the home buttons set home to {homes}")
    # The list scrolls with momentum, inside a clipped viewport.
    scroll = next(page.iter("ScrollConstraint"), None)
    physics = {p.get("id") for p in root.iter("ElasticScrollPhysics")}
    if scroll is None or scroll.get("physicsId") not in physics:
        failures.append("the list does not scroll with momentum")
    # The list tells the spider how far it scrolled: its offset is written
    # back to the page's view model, where page.luau reads it.
    back = [c for c in (scroll.findall("DataBindContext") if scroll is not None else [])
            if c.get("propertyKey") == "760" and c.get("direction") == "true"]
    if [names.get(c.get("sourcePathIds").split("-")[-1]) for c in back] != ["listScroll"]:
        failures.append("the list does not write its offset back to listScroll")
    if "getNumber('listScroll')" not in open(os.path.join(HERE, "page.luau")).read():
        failures.append("page.luau does not read listScroll")
    viewport = next((c for c in page.iter("LayoutComponent") if c.get("name") == "Viewport"), None)
    if viewport is None or viewport.get("clip") != "true":
        failures.append("the list's viewport does not clip")
    return failures


def main():
    root = ET.parse(os.path.join(HERE, "scene.rml")).getroot()
    failures = []
    legs = 0
    for femur in root.iter("RootBone"):
        name = femur.get("name").removesuffix(" Femur")
        tibia = femur.find("Bone")
        shapes = femur.findall("Shape") + tibia.findall("Shape")
        colour = [s for s in shapes if "Leg" in strokes(s)]
        outline = [s for s in shapes if "Outline" in strokes(s)]
        lower = [s for s in tibia.findall("Shape") if "Leg" in strokes(s)]
        legs += 1
        if len(colour) != 2 or len(outline) != 2 or len(lower) != 1:
            failures.append(f"{name}: expected 2 colour and 2 outline shapes")
            continue
        for s in colour:
            if "Outline" in strokes(s):
                failures.append(f"{name}: {s.get('name')} paints its own outline over the joint")
        for s in outline:
            rules = s.find("DrawRules")
            target = rules.find("DrawTarget") if rules is not None else None
            if (
                target is None
                or rules.get("drawTargetId") != target.get("id")
                or target.get("drawableId") != lower[0].get("id")
                or target.get("placementValue") != "after"
            ):
                failures.append(f"{name}: {s.get('name')} is not drawn behind the leg's lower colour")
    # Every rim sits the same width outside its part's outline, whatever the
    # outline's width, so the rims merge into one even silhouette.
    shapes = {s.get("name"): s for s in root.iter("Shape")}
    margins = set()
    for name, rim in shapes.items():
        if not name.endswith(" Rim"):
            continue
        part = shapes[name.removesuffix(" Rim")]
        outline = part.find("Stroke") if "Shape" not in name else shapes[name.replace(" Rim", " Outline")].find("Stroke")
        width = float(rim.find("Stroke").get("thickness"))
        margins.add(round(width - float(outline.get("thickness")), 4))
    if len(margins) != 1:
        failures.append(f"rims sit unevenly outside their outlines: {sorted(margins)}")
    # The z's over a sleeping head: white, with a black outline round it. In
    # a shape the last paint is on top.
    zs = [s for s in root.iter("Shape") if s.get("name") == "Z"]
    if not zs:
        failures.append("no z's")
    # They are the timelines' alone: their group sits where the body sleeps,
    # the middle of the view, with nothing bound for the script to move.
    _, view = rig()
    group = next(n for n in root.iter("Node") if n.find(".//Shape[@name='Z']") is not None and n.get("name", "").startswith("Zzz"))
    bound = any(b.get("propertyKey") in ("13", "14") for b in group.findall("DataBindContext"))
    if bound or (float(group.get("x", "0")), float(group.get("y", "0"))) != (view / 2, view / 2):
        failures.append("the z's are not placed over the sleeping body by the scene alone")
    for z in zs:
        paints = z.findall("Stroke")
        top, under = paints[-1], paints[-2]
        colour = lambda s: s.find("SolidColor").get("colorValue")
        if colour(top) != "FFFFFFFF" or under.get("name") != "Outline" or float(
            under.get("thickness")
        ) <= float(top.get("thickness")):
            failures.append("a z is not white over a wider outline")
            break
    # Timelines never fight the script. A "(code)" node is moved by the script
    # every frame, and a property bound to the view model is set by the bind
    # every frame, so a key on either is overwritten; the hierarchy's names
    # promise animators that. A bind that writes back (a knob) is the
    # exception: it reads what the timeline keys.
    by_id = {e.get("id"): e for e in root.iter() if e.get("id")}
    keyed = 0
    for obj in root.iter("KeyedObject"):
        target = by_id.get(obj.get("objectId"))
        if target is None:
            failures.append(f"a timeline keys {obj.get('objectId')}, which does not exist")
            continue
        name = target.get("name", "")
        if name.endswith("(code)"):
            failures.append(f"a timeline keys {name}")
        bound = {
            b.get("propertyKey") for b in target.findall("DataBindContext") if b.get("direction") != "true"
        }
        for p in obj.findall("KeyedProperty"):
            keyed += 1
            if p.get("propertyKey") in bound:
                failures.append(f"a timeline keys {name}'s bound property {p.get('propertyKey')}")
    if keyed == 0:
        failures.append("no timeline keys anything")
    # The Spider artboard is the character on its own: the size of the view a
    # host shows it through, and at rest it stands in the middle facing up,
    # so it reads in the editor before anything plays.
    rig_legs, view = rig()
    board = next(a for a in root.iter("Artboard") if a.get("name") == "Spider")
    if float(board.get("width")) != view or float(board.get("height")) != view:
        failures.append(f"Spider is {board.get('width')} by {board.get('height')}, not {view} square")
    d = defaults(root, "Spider")
    centre = view / 2
    if float(d["viewSize"]) != view or float(d["bodyX"]) != centre or float(d["bodyY"]) != centre:
        failures.append("the spider does not rest in the middle of its view")
    # The thought bubble and the z's are placed by the spider's head at rest.
    for name, off in (("Bubble (animate)", (52, -64)), ("Zzz", (0, 0))):
        n = next(n for n in board.iter("Node") if n.get("name") == name)
        if (float(n.get("x", 0)) - centre, float(n.get("y", 0)) - centre) != off:
            failures.append(f"{name} is not at {off} from the middle")
    for k, leg in enumerate(rig_legs):
        # Facing up: spider space (x, y) is (y, -x) on the artboard.
        want = (centre + leg["restY"], centre - leg["restX"])
        got = (float(d[f"foot{k}x"]), float(d[f"foot{k}y"]))
        if math.dist(want, got) > 0.01:
            failures.append(f"foot {k} rests at {got}, not {want}")
    # The legs the scripts walk with are the legs the scene draws: rig.luau's
    # hips and reach against each leg's bones.
    bones = {b.get("name").removesuffix(" Femur"): b for b in root.iter("RootBone")}
    src = open(os.path.join(HERE, "rig.luau")).read()
    for line, leg in zip([l for l in src.splitlines() if "name =" in l], rig_legs):
        name = re.search(r'name = "(\w+)"', line).group(1)
        femur = bones.get(name)
        if femur is None:
            failures.append(f"rig.luau has leg {name}, the scene does not")
            continue
        hip = (float(femur.get("x", "0")), float(femur.get("y", "0")))
        reach = float(femur.get("length")) + float(femur.find("Bone").get("length"))
        if math.dist(hip, (leg["hipX"], leg["hipY"])) > 0.01 or abs(reach - leg["reach"]) > 0.01:
            failures.append(f"{name}: rig.luau's hip or reach does not match its bones")
    # Desktop places it where the script says and passes it the pointer.
    desktop = next(a for a in root.iter("Artboard") if a.get("name") == "Desktop")
    nested = desktop.find("NestedArtboard")
    paths = {b.get("propertyKey"): b.get("sourcePathIds") for b in nested.findall("DataBindContext")}
    vm_ids = {p.get("name"): p.get("id") for p in root.iter() if p.tag.startswith("ViewModelProperty")}
    via = nested.get("dataBindPathIds")
    # An instance of its own on the placement (the editor adds one when the
    # placement is selected) would shadow Desktop's spider, which the host
    # writes the pointer to, and the spider would never move.
    if nested.find("ViewModelInstance") is not None:
        failures.append("Desktop's spider has a view model instance of its own, so the host cannot reach it")
    if via is None or paths.get("13") != f"{via}-{vm_ids['originX']}" or paths.get("14") != f"{via}-{vm_ids['originY']}":
        failures.append("Desktop does not place the spider at its origin")
    # Agent modes: an enum the state machine plays a timeline for, set by key
    # in Desktop (0 and 1 idle, 2-5 the rest) and by hotkey in the macOS app.
    modes = ["idle", "thinking", "working", "needsYou", "done"]
    enum = next((e for e in root.iter("DataEnumCustom") if e.get("name") == "Agent"), None)
    if enum is None or [v.get("key") for v in enum.findall("DataEnumValue")] != modes:
        failures.append(f"no Agent enum with {modes}")
    else:
        value_ids = {v.get("id"): v.get("key") for v in enum.findall("DataEnumValue")}
        agent = vm_ids.get("agent")
        layer = next((l for l in root.iter("StateMachineLayer") if l.get("name") == "Agent"), None)
        reached = set()
        for t in layer.iter("StateTransition") if layer is not None else []:
            for c in t.iter("TransitionValueEnumComparator"):
                reached.add((t.get("stateToId"), value_ids.get(c.get("value"))))
        states = {sid for sid, _ in reached}
        if layer is None or {m for _, m in reached} != set(modes) or len(states) != len(modes):
            failures.append("the Agent layer does not have a state for each mode")
        keys = {}
        for listener in desktop.iter("StateMachineListener"):
            k = listener.find(".//KeyboardInput")
            e = listener.find(".//BindablePropertyEnum")
            if k is not None and e is not None:
                bind = e.find("DataBindContext")
                if bind.get("sourcePathIds") == f"{via}-{agent}":
                    keys[k.get("keyType")] = value_ids.get(e.get("propertyValue"))
        want = {"key0": "idle", "key1": "idle", "key2": "thinking", "key3": "working", "key4": "needsYou", "key5": "done"}
        if keys != want:
            failures.append(f"Desktop's mode keys are {keys}, not {want}")
    # The eyes act out each mode: every Agent timeline sets both eyes' lids,
    # gaze and happy arcs (a timeline that left one out would inherit the
    # last mode's eyes), and done keeps its happy eyes while it rests.
    eye_parts = {n.get("id") for n in root.iter() if n.get("name") in ("Mood (animate)", "Look (animate)", "Happy (animate)")}
    if len(eye_parts) != 6:
        failures.append(f"expected a Mood, Look and Happy in each eye, found {len(eye_parts)}")
    for anim in root.iter("LinearAnimation"):
        name = anim.get("name", "")
        if not name.startswith("Agent") or name == "Agent Done Hop":
            continue
        keyed_eyes = {k.get("objectId") for k in anim.iter("KeyedObject")} & eye_parts
        if keyed_eyes != eye_parts:
            failures.append(f"{name} does not set both eyes")
        happy = [f for k in anim.iter("KeyedObject") if by_id.get(k.get("objectId"), ET.Element("x")).get("name") == "Happy (animate)"
                 for f in k.iter("KeyFrameDouble")]
        smiling = all(float(f.get("value", "0")) == 1 for f in happy) and happy
        if bool(smiling) != (name in ("Agent Done", "Agent Done Rest")):
            failures.append(f"{name} {'smiles' if smiling else 'does not smile'}")
        # A smile replaces the open eye: none of it may show round the arcs,
        # or the face reads as a broken, half-shut eye.
        mood_opacity = [f for k in anim.iter("KeyedObject") if by_id.get(k.get("objectId"), ET.Element("x")).get("name") == "Mood (animate)"
                        for p in k.iter("KeyedProperty") if p.get("property") == "opacity" for f in p.iter("KeyFrameDouble")]
        shown = sorted({float(f.get("value", "0")) for f in mood_opacity})
        if shown != ([0.0] if smiling else [1.0]):
            failures.append(f"{name} sets the open eye's opacity to {shown}")
    # Big, round eyes in every mode: moods show in the pupils and gaze, the
    # lids never narrow to slits (only blinks and sleep close them).
    for anim in root.iter("LinearAnimation"):
        name = anim.get("name", "")
        for k in anim.iter("KeyedObject"):
            part = by_id.get(k.get("objectId"), ET.Element("x"))
            if part.get("name") == "Mood (animate)" or (name.endswith(" Squint") and part.get("name", "").startswith("Eye ")):
                for p in k.iter("KeyedProperty"):
                    if p.get("property") == "scaleX" and any(float(f.get("value", "0")) < 0.85 for f in p.iter("KeyFrameDouble")):
                        failures.append(f"{name} narrows {part.get('name')} to a slit")
    for eye in (n for n in root.iter("Node") if n.get("name") in ("Eye L", "Eye R")):
        white = next(sh for sh in eye.iter("Shape") if sh.get("name") == "White").find("Ellipse")
        if float(white.get("width")) < 12 or float(white.get("height")) < 13:
            failures.append(f"{eye.get('name')} is {white.get('width')} by {white.get('height')}, not big and cute")
    # The brain draws the silk, under everything else on the Spider artboard:
    # it is the last drawable there.
    spider_ab = next(a for a in root.iter("Artboard") if a.get("name") == "Spider")
    drawables = [c for c in spider_ab if c.tag in ("Node", "Shape", "LayoutComponent")]
    if not drawables or drawables[-1].get("name") != "Brain (code)":
        failures.append("the brain, which draws the silk, is not under the spider")
    # Grooming: the script says when (the grooming boolean), the Groom
    # timeline how, on the front feet's Pose nodes, in a layer after Agent's
    # so it wins while it plays.
    layers = [l.get("name") for l in spider_ab.iter("StateMachineLayer")]
    groom = next((a for a in root.iter("LinearAnimation") if a.get("name") == "Groom"), None)
    keyed = {by_id.get(k.get("objectId"), ET.Element("x")).get("name") for k in groom.iter("KeyedObject")} if groom is not None else set()
    if keyed != {"Foot L1 Pose (animate)", "Foot R1 Pose (animate)"}:
        failures.append(f"the Groom timeline keys {sorted(keyed)}, not the front feet's poses")
    if "Groom" not in layers or layers.index("Groom") < layers.index("Agent"):
        failures.append("no Groom layer after the Agent layer")
    else:
        layer = next(l for l in spider_ab.iter("StateMachineLayer") if l.get("name") == "Groom")
        if not any(b.get("sourcePathIds", "").endswith(f"-{vm_ids.get('grooming')}") for b in layer.iter("DataBindContext")):
            failures.append("the Groom layer does not follow the grooming boolean")
    # Desktop's window moves as one piece, so its title bar can drag it.
    desktop = next(a for a in root.iter("Artboard") if a.get("name") == "Desktop")
    window = next((n for n in desktop.iter("Node") if n.get("name") == "Window (code)"), None)
    if window is None or {"Title Bar", "Window"} - {c.get("name") for c in window.iter("Shape")}:
        failures.append("Desktop's window is not one node holding its title bar and frame")
    elif {b.get("propertyKey") for b in window.findall("DataBindContext")} != {"13", "14"}:
        failures.append("Desktop's window position is not bound")
    # h sends the spider home, f has it follow.
    home_keys = {}
    for lis in desktop.iter("StateMachineListener"):
        k = lis.find(".//KeyboardInput")
        b = lis.find(".//BindablePropertyBoolean")
        if k is not None and b is not None and b.find("DataBindContext").get("sourcePathIds", "").endswith(f"-{vm_ids.get('home')}"):
            home_keys[k.get("keyType")] = b.get("propertyValue") == "true"
    if home_keys != {"h": True, "f": False}:
        failures.append(f"Desktop's home keys are {home_keys}")
    # The happy arcs are light, so they read on the dark head.
    for happy in (n for n in root.iter("Shape") if n.get("name") == "Happy (animate)"):
        top = happy.findall("Stroke")[-1].find("SolidColor")
        if top is None or min(int(top.get("colorValue")[i:i + 2], 16) for i in (2, 4, 6)) < 0xC0:
            failures.append("the happy arcs are not drawn in a light colour")
    # Dust scatters: specks of different sizes thrown different distances
    # from where the foot lands, not one ring spreading out.
    dust = next(n for n in root.iter("Node") if n.get("name") == "Dust (animate)")
    puff = next(a for a in root.iter("LinearAnimation") if a.get("name") == "Puff")
    if dust.find("Shape/Stroke") is not None or any(s.get("name") == "Ring" for s in dust.iter("Shape")):
        failures.append("the dust puff still has a ring")
    ends, sizes = [], set()
    for mote in dust.iter("Shape"):
        e = mote.find("Ellipse")
        sizes.add(round(float(e.get("width")), 1))
        k = next(k for k in puff.iter("KeyedObject") if k.get("objectId") == mote.get("id"))
        last = lambda prop: next((float(p.findall("KeyFrameDouble")[-1].get("value", "0"))
                                  for p in k.iter("KeyedProperty") if p.get("property") == prop), 0.0)
        ends.append(math.hypot(last("x"), last("y")))
    if len(ends) < 8 or max(ends) < 2 * min(ends) or len(sizes) < 5 or max(sizes) > 8:
        failures.append(f"the dust does not scatter: {len(ends)} specks, {len(sizes)} sizes up to {max(sizes)}, thrown {min(ends):.0f} to {max(ends):.0f}")
    # Feet darken a little towards the tip, not into a black shoe.
    for tip in (s for s in root.iter("Stroke") if s.get("name") == "Tip"):
        darkest = max(int(g.get("colorValue")[:2], 16) for g in tip.iter("GradientStop"))
        if darkest > 0x50:
            failures.append(f"a foot tip darkens to alpha {darkest:#x}")
    # Foot poses are keyed in the spider's own space: forward is forward
    # whichever way it faces.
    for foot in root.iter("Node"):
        if foot.get("name", "").startswith("Foot ") and foot.get("name").endswith("(code)"):
            if not any(b.get("propertyKey") == "15" and b.get("sourcePathIds", "").endswith(f"-{vm_ids['bodyRot']}") for b in foot.findall("DataBindContext")):
                failures.append(f"{foot.get('name')} does not turn with the body")
    # Outlines are a darker shade of the part they draw round, not one ink for
    # everything: the part's own colour with a dark tone over it, so each
    # palette gets its own outline.
    colour_bind = lambda paint: next(
        (b.get("sourcePathIds", "").split("-")[-1] for b in paint.iter("DataBindContext")), None)
    for shape in root.iter("Shape"):
        name = shape.get("name", "")
        if name.endswith(" Shape Outline"):
            own = vm_ids["leg"]
        elif name in ("Head", "Abdomen"):
            own = vm_ids["bodyBottom"]
        else:
            continue
        paints = [p for p in shape.findall("Stroke") if p.get("name") in ("Outline", "Stroke", "Tone")]
        tone = [p for p in paints if p.get("name") == "Tone"]
        base = [p for p in paints if p.get("name") != "Tone"]
        if len(base) != 1 or colour_bind(base[0]) != own or len(tone) != 1 or paints.index(tone[0]) < paints.index(base[0]) \
                or tone[0].get("thickness") != base[0].get("thickness"):
            failures.append(f"{name}'s outline is not a tone of its own colour")
    # One light, from the top left of the screen: every shadow falls down and
    # to the right of what casts it, and every shade inside a part sits on
    # its lower right (an inner feather's offset points the other way).
    offsets = []
    for node in root.iter("Node"):
        if node.get("name") == "Offset":
            offsets.append((node.get("name"), float(node.get("x", "0")), float(node.get("y", "0"))))
    for shape in root.iter("Shape"):
        for paint in list(shape.findall("Fill")) + list(shape.findall("Stroke")):
            f = paint.find("Feather")
            if f is None or (f.get("offsetX") is None and f.get("offsetY") is None):
                continue
            dx, dy = float(f.get("offsetX", "0")), float(f.get("offsetY", "0"))
            inner, kind = f.get("inner") == "true", paint.get("name")
            if inner and kind == "Shade":
                dx, dy = -dx, -dy
            elif not (inner and kind == "Light") and kind != "Shadow":
                continue
            offsets.append((f"{shape.get('name')} {kind}", dx, dy))
    for name, dx, dy in offsets:
        if dx <= 0 or dy <= 0:
            failures.append(f"{name} is not lit from the top left")
    if len(offsets) < 20:
        failures.append(f"only {len(offsets)} shadows and shades checked")
    # The scene's colours are the menu's first palette, so the editor shows
    # what the app starts with.
    swift = open(os.path.join(HERE, "mac", "Sources", "Palette.swift")).read()
    first = re.search(r'Palette\(name: "[^"]*", colors: \[(.*?)\]', swift, re.S).group(1)
    want = {k: v.upper() for k, v in re.findall(r'"(\w+)": 0x([0-9A-Fa-f]{8})', first)}
    got = {k: v.upper() for k, v in defaults(root, "Spider").items() if k in want}
    if got != want:
        failures.append(f"the scene's colours {got} are not the first palette's {want}")
    failures += silkworks(root, swift)
    if legs != 8:
        failures.append(f"expected 8 legs, found {legs}")
    for f in failures:
        print("FAIL", f)
    print(f"{legs} legs checked, {len(failures)} failed")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
