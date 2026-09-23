#!/usr/bin/env python3
"""
What each house is checked against: where a player must be able to walk, where
they must not, and what the preview renders look at.

Everything here is in house space: +X right, +Y up, +Z out of the front door,
with Y = 0 the ground floor. The capture is built against a pivot that puts
the ground at world Y = 0, so world = house + (0, G, 0), G being the house's
foundation height.
"""

HOUSES = {}

# --------------------------------------------------------------------------
# House #1: the manor
# --------------------------------------------------------------------------

_L1, _L2, _L3 = 0, 14, 28
_GS_LAND_Y = 10 * 14 / 18
_AS_LAND_Y = 14 + 8 * 14 / 18

HOUSES["Manor"] = dict(
    G=7,
    bounds=dict(x=(-62, 66), y=(-11, 80), z=(-64, 64)),
    seed=(22, -7, 52),
    floors=[("ground", _L1), ("first", _L2), ("attic", _L3)],
    # For nav.py --exits. The manor is not sealed: its windows are glassless
    # and a player can climb out of them, which --exits will show.
    inside=(0, _L1, 12),
    targets=[
        ("front steps foot", (22, -7, 52)),
        ("round the back, on the grass", (0, -7, -40)),
        ("porch, right end", (46, _L1, 34)),
        ("porch, left end by the bay", (-14, _L1, 34)),
        ("porch return", (47, _L1, 23)),
        ("back stoop", (-31, _L1, -33)),
        ("hall", (0, _L1, 12)),
        ("hall, foot of the stairs", (-8, _L1, -4)),
        ("stair well", (-1, _L1, -15)),
        ("grand stair A, mid flight", (-8, 4, -15)),
        ("half landing", (0, _GS_LAND_Y, -25)),
        ("grand stair B, mid flight", (8, 11, -16)),
        ("parlour", (-28, _L1, 4)),
        ("parlour bay", (-33, _L1, 36)),
        ("kitchen", (-20, _L1, -22)),
        ("drawing room", (22, _L1, 22)),
        ("library", (21, _L1, -8)),
        ("gallery", (-6, _L2, -9.4)),
        ("dining hall, middle", (0, _L2, 21)),
        ("dining hall, left end", (-30, _L2, 22)),
        ("dining hall, right end", (30, _L2, 22)),
        ("dining bay", (-28, _L2, 37)),
        ("bedroom", (-30, _L2, -21)),
        ("bathroom", (19, _L2, -15)),
        ("attic stair hall", (30, _L2, -10.5)),
        ("attic stair C, mid flight", (37.5, 17, -16)),
        ("attic stair landing", (33, _AS_LAND_Y, -26)),
        ("attic stair D, mid flight", (29.5, 24, -16)),
        ("attic, centre", (0, _L3, -10)),
        ("attic, left end", (-30, _L3, 0)),
        ("attic, right", (18, _L3, 5)),
        ("attic, bay", (-28, _L3, 34)),
        ("attic, front dormer", (22, _L3, 26)),
    ],
    forbidden=[
        ("porch roof", (15, 15.5, 34)),
        ("main roof, front slope", (0, 52, 16)),
        ("main roof, back slope", (0, 52, -16)),
        ("bay roof", (-28, 44, 36)),
    ],
    views=dict(
        cut=[("11-cut-ground.png", 9.5), ("12-cut-first.png", _L2 + 9.5), ("13-cut-attic.png", _L3 + 8)],
        eye=[
            # name, eye, target (house space)
            ("20-hall.png", (3, 4.6, 24), (-6, 5, -10)),
            ("21-stair.png", (-1, 4.6, 2), (0, 7, -22)),
            ("22-parlour.png", (-16, 4.6, 26), (-34, 3, 8)),
            ("23-kitchen.png", (-33, 4.6, -8), (-18, 3, -26)),
            ("24-drawing.png", (15.5, 4.6, 19), (38, 3, 6)),
            ("25-library.png", (16, 4.6, -3), (34, 4, -24)),
            ("26-dining.png", (-36, _L2 + 5.5, 26), (10, _L2 + 3, 4)),
            ("27-dining-table.png", (22, _L2 + 6, 20), (0, _L2 + 3, 10)),
            ("28-gallery.png", (6, _L2 + 4.8, 4), (-4, _L2 + 1, -24)),
            ("29-bedroom.png", (-18, _L2 + 4.8, -9.5), (-36, _L2 + 3, -24)),
            ("30-bathroom.png", (22.5, _L2 + 4.8, -13), (15, _L2 + 2, -26)),
            ("31-attic.png", (26, _L3 + 5, -6), (-20, _L3 + 3, 10)),
            ("32-porch.png", (48, 4.6, 36), (0, 5, 32)),
            ("33-landing.png", (0, _GS_LAND_Y + 4.6, -25), (0, _L2 + 2, -4)),
        ],
    ),
)

# --------------------------------------------------------------------------
# House #2: the villa
# --------------------------------------------------------------------------

_V2, _V3 = 15, 30
_VLAND = 7.5

HOUSES["Villa"] = dict(
    G=4,
    bounds=dict(x=(-46, 46), y=(-5, 62), z=(-48, 54)),
    seed=(0, -4, 43),
    floors=[("ground", 0), ("first", _V2), ("roof", _V3)],
    # Exactly two ways out was part of the brief, so nav.py always proves it
    # for this house: with every door shut, a flood from `inside` must not
    # reach the ground outside.
    sealed=True,
    inside=(0, 0, 10),
    targets=[
        ("portico steps foot", (0, -4, 43)),
        ("back stoop steps foot", (-14, -4, -40)),
        ("round the side, on the grass", (40, -4, 0)),
        ("portico", (0, 0, 30)),
        ("hall, front", (0, 0, 20)),
        ("hall, foot of the stairs", (0, 0, -6.5)),
        ("between the flights", (0, 0, -14)),
        ("flight A, mid", (-5, 3.75, -14)),
        ("half landing", (0, _VLAND, -22.5)),
        ("flight B, mid", (5, 11.25, -14)),
        ("parlour", (-14, 0, 5)),
        ("kitchen", (-15, 0, -18)),
        ("dining room", (13, 0, 22)),
        ("library", (22, 0, -8)),
        ("first-floor hall", (0, _V2, 10)),
        ("first-floor, between the flights", (0, _V2, -14)),
        ("master bedroom", (-24, _V2, 16)),
        ("second bedroom", (-24, _V2, -8)),
        ("nursery", (24, _V2, 12)),
        ("sewing room", (20, _V2, -3)),
        ("bathroom", (24, _V2, -18)),
        ("flight C, mid", (-5, _V2 + 3.75, -14)),
        ("upper landing", (0, _V2 + _VLAND, -22.5)),
        ("flight D, mid", (5, _V2 + 11.25, -14)),
        ("belvedere", (-4, _V3, -16)),
        ("roof, front", (0, _V3, 12)),
        ("roof, left", (-20, _V3, -12)),
        ("roof, right", (20, _V3, -12)),
        ("roof, back corner", (-26, _V3, -22)),
    ],
    forbidden=[
        ("parapet coping, front", (0, 35, 25.5)),
        ("parapet coping, side", (31.5, 35, 0)),
        ("cornice outside the parapet", (33.5, 30.5, 0)),
        ("belvedere roof", (0, 45, -14)),
        ("portico roof", (0, 14.5, 30)),
        ("chimney top", (-32, 45, 14)),
    ],
    views=dict(
        cut=[("11-cut-ground.png", 9.5), ("12-cut-first.png", _V2 + 9.5), ("13-cut-roof.png", _V3 + 8)],
        eye=[
            ("20-hall.png", (0, 4.6, 23), (0, 4, -12)),
            ("21-stair.png", (0, 4.6, -3), (0, 7, -22)),
            ("22-parlour.png", (-12, 5.5, 3.5), (-24, 3, 20)),
            ("23-kitchen.png", (-12, 4.6, -1), (-28, 3, -18)),
            ("24-dining.png", (12, 5.5, 2.8), (24, 3, 20)),
            ("25-library.png", (11.5, 4.6, 0), (28, 4, -20)),
            ("26-upper-hall.png", (0, _V2 + 4.8, 23), (0, _V2 + 2, -10)),
            ("27-master.png", (-13, _V2 + 5, 14), (-26, _V2 + 2, 4)),
            ("28-bedroom.png", (-11, _V2 + 4.8, 0), (-26, _V2 + 2, -22)),
            ("29-nursery.png", (11, _V2 + 4.8, 23), (24, _V2 + 1, 8)),
            ("30-sewing.png", (11, _V2 + 4.8, 0), (30, _V2 + 2, -4)),
            ("31-bathroom.png", (26, _V2 + 4.8, -9.5), (14, _V2 + 1, -24)),
            ("32-belvedere.png", (-6, _V3 + 4.8, -4), (4, _V3 + 2, -22)),
            ("33-roof.png", (-26, _V3 + 5, 20), (10, _V3 + 4, -10)),
            ("34-portico.png", (6, 5, 40), (0, 6, 26)),
            ("35-landing.png", (0, _VLAND + 4.6, -22), (0, _V2 + 2, 0)),
        ],
    ),
)

# --------------------------------------------------------------------------
# House #3: the lodge
# --------------------------------------------------------------------------

HOUSES["Lodge"] = dict(
    G=3,
    bounds=dict(x=(-58, 58), y=(-4, 52), z=(-46, 52)),
    seed=(0, -3, 44),
    floors=[("ground", 0)],
    inside=(0, 0, 10),
    targets=[
        ("porch steps foot", (0, -3, 44)),
        ("back step foot", (-8, -3, -39)),
        ("round the east gable", (54, -3, 0)),
        ("porch, left end", (-26, 0, 33)),
        ("porch, right end", (26, 0, 33)),
        ("great room, by the door", (0, 0, 22)),
        ("great room, by the fire", (-11, 0, 7)),
        ("great room, the long table", (1, 0, 14)),
        ("bunk room", (-24, 0, 12)),
        ("bath", (-32, 0, 5)),
        ("store cupboard", (-22, 0, 4.5)),
        ("kitchen", (-22, 0, -8)),
        ("mud room", (-9, 0, -18)),
        ("workshop", (10, 0, -11)),
        ("trophy room", (28, 0, -10)),
        ("master bedroom", (22, 0, 20)),
        ("washroom", (22, 0, 4)),
        ("gun cupboard", (33, 0, 4)),
    ],
    forbidden=[
        ("roof, front slope", (0, 30, 12)),
        ("roof, back slope", (0, 30, -12)),
        ("porch roof", (0, 10, 33)),
        ("chimney top", (0, 44, -8)),
        ("tie beam", (10.5, 14.5, 10)),
    ],
    views=dict(
        cut=[("11-cut.png", 9.5)],
        eye=[
            ("20-great-room.png", (0, 5, 24), (0, 8, -6)),
            ("21-fireplace.png", (-12, 5, 16), (2, 6, -4)),
            ("22-vault.png", (-12, 4.5, 24), (8, 26, -2)),
            ("23-kitchen.png", (-18.5, 5, -2), (-38, 3, -20)),
            ("24-bunk.png", (-18, 5, 25), (-40, 3, 10)),
            ("25-trophy.png", (18, 5, -2), (40, 4, -22)),
            ("26-workshop.png", (2, 5, -10), (14, 4, -24)),
            ("27-mudroom.png", (-2, 5, -10), (-14, 4, -26)),
            ("28-master.png", (18, 5, 25), (40, 3, 10)),
            ("29-porch.png", (-28, 4.6, 34), (20, 4, 33)),
            ("30-bath.png", (-29.5, 5, 7), (-42, 3, 1)),
        ],
    ),
)

# --------------------------------------------------------------------------
# The church and its churchyard
# --------------------------------------------------------------------------

_BELFRY = 36

HOUSES["Church"] = dict(
    G=2,
    bounds=dict(x=(-72, 66), y=(-4, 100), z=(-98, 76)),
    seed=(0, -2, 42),
    floors=[("nave", 0), ("belfry", _BELFRY)],
    inside=(0, 0, 10),
    targets=[
        ("west steps foot", (0, -2, 38)),
        ("nave, by the west door", (0, 0, 24)),
        ("nave, middle aisle", (0, 0, 4)),
        ("north aisle", (-11.5, 0, 0)),
        ("south aisle", (11.5, 0, -4)),
        ("under the chancel arch", (0, 0, -27)),
        ("chancel", (0, 0.8, -33)),
        ("sanctuary", (0, 1.6, -46)),
        ("vestry", (-11.5, 0, -40)),
        ("outside the vestry door", (-10, -2, -49)),
        ("porch", (21, 0, 14)),
        ("porch steps foot", (30, -2, 14)),
        ("tower, by the door", (-19, 0, 23)),
        ("tower stair, first corner", (-29.25, 4.5, 28.25)),
        ("tower stair, third corner", (-18.75, 13.5, 17.75)),
        ("tower stair, sixth corner", (-29.25, 27, 17.75)),
        ("belfry", (-24, _BELFRY, 28.2)),
        ("belfry, by the bell", (-29.5, _BELFRY, 27)),
        ("the lane, outside the lych-gate", (0, -2, 72)),
        ("under the lych-gate", (0, -2, 66)),
        ("churchyard, north side", (-52, -2, 0)),
        ("churchyard, south side", (46, -2, 0)),
        ("behind the chancel", (0, -2, -70)),
        ("by the open grave", (13, -2, -63)),
        ("mausoleum steps", (44, -2, -66)),
        ("the fields, through the wicket gate", (-10, -2, -96)),
        ("outside, through the fallen wall", (-70, -2, -27)),
    ],
    forbidden=[
        ("lych-gate roof", (0, 9.9, 63.5)),
        ("mausoleum roof", (41, 11.6, -76.7)),
        ("nave roof", (4, 37.2, 0)),
        ("south aisle roof", (12, 19.9, 0)),
        ("north aisle roof", (-12, 19.9, -8)),
        ("chancel roof", (3, 31, -40)),
        ("tower top", (-32, 53, 15.5)),
        ("porch roof", (21, 11.9, 11)),
        ("vestry roof", (-12, 13.3, -36)),
    ],
    views=dict(
        cut=[("11-cut-ground.png", 9.5), ("12-cut-belfry.png", _BELFRY + 9)],
        eye=[
            ("20-nave.png", (0, 4.6, 26), (0, 6, -40)),
            ("21-chancel-west.png", (0, 5.4, -44), (0, 9, 20)),
            ("22-north-aisle.png", (-11.5, 4.6, 26), (-10, 5, -22)),
            ("23-tower-well.png", (-19, 4.6, 29), (-24, 30, 22)),
            ("24-belfry.png", (-18.5, _BELFRY + 4.6, 28.5), (-26, _BELFRY + 6, 21)),
            ("25-porch.png", (24, 4.6, 14), (14, 5, 14)),
            ("26-vestry.png", (-9.5, 4.6, -30), (-14, 3, -42)),
            ("27-sanctuary.png", (4, 5.4, -30), (-2, 6, -50)),
            ("28-lychgate.png", (0, 2.6, 78), (0, 4, 30)),
            ("29-graves-south.png", (50, 2.6, 34), (38, 1, -40)),
            ("30-mausoleum.png", (34, 2.6, -58), (44, 5, -80)),
            ("31-open-grave.png", (5, 3.4, -61), (14, -3, -72)),
            ("32-graves-north.png", (-38, 2.6, 60), (-56, 1, -30)),
            ("33-behind-chancel.png", (26, 4.6, -52), (-20, 2, -80)),
        ],
    ),
)
