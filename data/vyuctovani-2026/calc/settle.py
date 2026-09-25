"""Suchá electricity settlement for the invoice period, from events.csv + invoice.json.

events.csv is the canonical merged record (paper notebook + app data). Presence is derived
from check_in/check_out rows; consumption between consecutive readings is split equally
among the payers (households) present. See ../README.md for the rules.
"""
import csv
import json
import os
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.dirname(HERE)
INV = json.load(open(os.path.join(DATA, "invoice.json")))

VAT = 1 + INV["vat"]
FIXED = INV["fixed_incl_vat"]                     # jistič, stálý plat, nesíťová infrastruktura
VARIABLE = round(INV["total_incl_vat"] - FIXED, 2)
PRICE = {}                                        # Kč/kWh incl VAT
for y, u in INV["unit_prices_excl_vat_kc_per_mwh"].items():
    base = u["supply"] + u["poze"] + u["system_services"] + u["electricity_tax"]
    PRICE[int(y)] = {"VT": (base + u["dist_VT"]) / 1000 * VAT, "NT": (base + u["dist_NT"]) / 1000 * VAT}

FAMILIES = ["Jirka", "Kristina", "Potužníci"]     # share fixed charges + empty-house consumption
PAYER = {"Jirka": "Jirka", "Johana": "Jirka", "Kristina": "Kristina",
         "Petr": "Potužníci", "Tereza": "Potužníci", "Bára": "Potužníci",
         "Edita": "Edita", "Marek": "Marek"}
GARAGE_OWNER = "Jirka"   # garage sub-meter sits behind the main meter; only Jirka's family uses it

start = INV["period"][0] + " 00:00"
end = INV["period"][1] + " 23:59"
rows = [r for r in csv.DictReader(open(os.path.join(DATA, "events.csv"), encoding="utf-8"))
        if start <= r["at"] <= end and r["status"] != "pending"]

# --- walk events: build intervals between readings with who was present ----------------
present = set()
points = []          # (at, vt, nt, garage_or_None, present_after)
charges = []         # (at, visitor, kwh)
for r in rows:
    if r["action"] == "manual_kwh":
        charges.append((r["at"], r["visitor"], float(r["kwh"])))
        continue
    if r["action"] == "check_in":
        present.add(r["visitor"])
    elif r["action"] == "check_out":
        present.discard(r["visitor"])
    points.append((r["at"], float(r["vt"]), float(r["nt"]),
                   float(r["garage"]) if r["garage"] else None, frozenset(present)))
assert (points[0][1], points[0][2]) == (INV["readings"]["start"]["VT"], INV["readings"]["start"]["NT"])
assert (points[-1][1], points[-1][2]) == (INV["readings"]["end"]["VT"], INV["readings"]["end"]["NT"])
assert not points[-1][4], f"still present at period end: {points[-1][4]}"

intervals = []
for (a, vt0, nt0, _, pres), (b, vt1, nt1, _, _) in zip(points, points[1:]):
    vt, nt = vt1 - vt0, nt1 - nt0
    assert vt >= 0 and nt >= 0, f"meter went backwards {a}->{b}"
    intervals.append({"from": a, "to": b, "VT": vt, "NT": nt,
                      "payers": sorted({PAYER[v] for v in pres}), "garage": 0.0, "ev": []})

# garage: spread each delta between written garage readings over the Jirka-family
# intervals inside that span, proportional to their consumption
known = [(i, p[3]) for i, p in enumerate(points) if p[3] is not None]
for (i0, g0), (i1, g1) in zip(known, known[1:]):
    delta = g1 - g0
    if delta <= 0:
        continue
    span = [iv for iv in intervals[i0:i1] if GARAGE_OWNER in iv["payers"]]
    assert span, f"garage moved {points[i0][0]}->{points[i1][0]} without {GARAGE_OWNER} present"
    tot = sum(iv["VT"] + iv["NT"] for iv in span)
    for iv in span:
        iv["garage"] += delta * (iv["VT"] + iv["NT"]) / tot

for at, visitor, kwh in charges:   # EV charging -> interval containing its timestamp
    iv = next(iv for iv in intervals if iv["from"] <= at < iv["to"])
    assert PAYER[visitor] in iv["payers"], f"{visitor} charging at {at} while not present"
    iv["ev"].append((visitor, kwh))

# --- allocate ------------------------------------------------------------------------
alloc = defaultdict(lambda: {"VT": 0.0, "NT": 0.0, "Kc": 0.0})
empty = {"VT": 0.0, "NT": 0.0, "Kc": 0.0}
detail = []


def price(year, vt, nt):
    return vt * PRICE[year]["VT"] + nt * PRICE[year]["NT"]


for iv in intervals:
    vt, nt = iv["VT"], iv["NT"]
    if vt == 0 and nt == 0:
        continue
    year = int(iv["from"][:4])
    fv, fn = vt / (vt + nt), nt / (vt + nt)

    def charge(payer, v, n, why):
        a = alloc[payer]
        a["VT"] += v; a["NT"] += n; a["Kc"] += price(year, v, n)
        detail.append({"from": iv["from"], "to": iv["to"], "payer": payer,
                       "VT": round(v, 2), "NT": round(n, 2), "Kc_tariff": round(price(year, v, n), 2), "why": why})

    if not iv["payers"]:
        empty["VT"] += vt; empty["NT"] += nt; empty["Kc"] += price(year, vt, nt)
        detail.append({"from": iv["from"], "to": iv["to"], "payer": "prázdný dům",
                       "VT": vt, "NT": nt, "Kc_tariff": None, "why": "nikdo nebyl přítomen"})
        continue
    rv, rn = vt, nt
    for visitor, kwh in iv["ev"]:
        charge(PAYER[visitor], kwh * fv, kwh * fn, f"nabíjení auta {kwh:g} kWh")
        rv -= kwh * fv; rn -= kwh * fn
    if iv["garage"] and len(iv["payers"]) > 1:
        g = iv["garage"]
        charge(GARAGE_OWNER, g * fv, g * fn, f"garáž {g:.1f} kWh")
        rv -= g * fv; rn -= g * fn
    n = len(iv["payers"])
    for p in iv["payers"]:
        charge(p, rv / n, rn / n, "sám/sama" if n == 1 else "sdíleno " + "+".join(iv["payers"]))

attributed = sum(a["Kc"] for a in alloc.values()) + empty["Kc"]
scale = VARIABLE / attributed   # PPAS priced more kWh at 2025 rates (estimated split); reconcile to invoice

out_rows = []
for p in FAMILIES + ["Edita", "Marek"]:
    a = alloc[p]
    fam = p in FAMILIES
    own, emp, fix = a["Kc"] * scale, (empty["Kc"] * scale / 3 if fam else 0), (FIXED / 3 if fam else 0)
    out_rows.append({"payer": p, "VT": round(a["VT"], 1), "NT": round(a["NT"], 1), "kwh": round(a["VT"] + a["NT"], 1),
                     "own_kc": round(own, 2), "empty_kwh": round((empty["VT"] + empty["NT"]) / 3, 1) if fam else 0,
                     "empty_kc": round(emp, 2), "fixed_kc": round(fix, 2), "total_kc": round(own + emp + fix, 2)})

tot_vt = sum(a["VT"] for a in alloc.values()) + empty["VT"]
tot_nt = sum(a["NT"] for a in alloc.values()) + empty["NT"]
assert abs(tot_vt - INV["consumption_kwh"]["VT"]) < 0.01 and abs(tot_nt - INV["consumption_kwh"]["NT"]) < 0.01
print(json.dumps({
    "check": {"VT": round(tot_vt, 3), "NT": round(tot_nt, 3), "tariff_kc": round(attributed, 2),
              "invoice_variable_kc": VARIABLE, "scale": round(scale, 5),
              "sum_total": round(sum(r["total_kc"] for r in out_rows), 2)},
    "prices": {y: {k: round(v, 4) for k, v in d.items()} for y, d in PRICE.items()},
    "empty": {k: round(v, 2) for k, v in empty.items()},
    "rows": out_rows, "detail": detail}, ensure_ascii=False, indent=1))
