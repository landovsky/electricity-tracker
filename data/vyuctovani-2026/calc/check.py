"""Cross-check the generated pages against the invoice, out.json and advances.csv.

Reads the numbers back out of the rendered HTML (what the family actually sees), so a
template or rounding slip shows up here even if settle.py is right. The live even split
("Rozdělit mezi členy") is exercised in headless Chrome for every combination of ticked
members.  Run after build.py:  python3 check.py
"""
import csv
import json
import os
import re
import subprocess
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.dirname(HERE)
INV = json.load(open(os.path.join(DATA, "invoice.json")))
OUT = json.load(open(os.path.join(HERE, "out.json")))
ADV = list(csv.DictReader(open(os.path.join(DATA, "advances.csv"), encoding="utf-8")))
SLUG = {"Jiří": "jiri", "Kristina": "kristina", "Petr": "petr"}
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
fails = []


def ok(cond, msg):
    print(("  ok   " if cond else "  FAIL ") + msg)
    if not cond:
        fails.append(msg)


def num(s):
    s = re.sub(r"<[^>]+>", "", s).replace("&#8239;", "").replace("&nbsp;", "").replace("\u202f", "")
    s = s.replace("\xa0", "").replace(" ", "").replace("−", "-").replace("+", "").replace("Kč", "").replace(",", ".")
    try:
        return float(s) if s else 0.0
    except ValueError:
        return float("nan")   # text cell (e.g. "vrací se …")


def cells(tr):
    return [num(c) for c in re.findall(r"<td[^>]*>(.*?)</td>", tr, re.S)]


def section(html, start, end="</table>"):
    i = html.index(start)
    return html[i:html.index(end, i)]


def eq(a, b):
    return abs(a - b) < 0.005


page = open(os.path.join(DATA, "vyuctovani-sucha-2026.html")).read()
rows = {r["payer"]: r for r in OUT["rows"]}
total = INV["total_incl_vat"]

print("invoice")
ok(eq(sum(r["total_kc"] for r in rows.values()), total), f"branch totals sum to invoice {total}")
ok(eq(sum(r["fixed_kc"] for r in rows.values()), INV["fixed_incl_vat"]), "fixed thirds sum to invoice fixed part")
ok(eq(sum(r["own_kc"] + r["empty_kc"] for r in rows.values()), total - INV["fixed_incl_vat"]), "consumption sums to invoice variable part")
kwh = sum(r["kwh"] for r in rows.values()) + OUT["empty"]["VT"] + OUT["empty"]["NT"]
ok(abs(kwh - sum(INV["consumption_kwh"].values())) < 0.2, f"kWh sum {kwh:.1f} = invoice {sum(INV['consumption_kwh'].values())}")
for p, r in rows.items():
    ok(eq(r["own_kc"] + r["empty_kc"] + r["fixed_kc"], r["total_kc"]), f"{p}: direct + empty + fixed = total")

print("advances")
adv_sum = {p: sum(float(a["kc"]) for a in ADV if a["payer"] == p) for p in rows}
for p, r in rows.items():
    ok(eq(r["advances_kc"], adv_sum[p]), f"{p}: advances {r['advances_kc']} = bank export")
    ok(eq(r["balance_kc"], r["advances_kc"] - r["total_kc"]), f"{p}: balance = advances − share")
    n = sum(1 for a in ADV if a["payer"] == p)
    ok(n == 11 and not any(a["date"] < "2025-10-01" for a in ADV if a["payer"] == p), f"{p}: 11 payments, none from September 2025")
refunds = sum(r["balance_kc"] for r in rows.values())
account = sum(adv_sum.values()) - INV["advances_paid"] + INV["overpayment_refund"]
ok(abs(account - refunds) < 0.10, f"shared account after PPAS {account:.2f} covers refunds {refunds:.2f} (diff {account - refunds:.2f})")

print("common page")
settle = section(page, "<h2>Vyrovnání záloh</h2>")
for p, r in rows.items():
    tr = re.search(rf"<tr>.*?{SLUG[p]}.*?</tr>|<tr><th scope=\"row\"><span[^>]*>.</span>{p}.*?</tr>", settle, re.S)
    c = cells(tr.group(0))
    ok(eq(c[0], r["advances_kc"]) and eq(c[1], r["total_kc"]) and eq(c[2], r["balance_kc"]), f"{p}: advances row shows {c[:3]}")
foot = cells(re.search(r"<tfoot>.*?</tfoot>", settle, re.S).group(0))
ok(eq(foot[0], sum(adv_sum.values())) and eq(foot[1], total) and eq(foot[2], refunds), f"advances footer {foot[:3]}")
summ = section(page, "<h2>Kolik kdo platí</h2>")
for p, r in rows.items():
    c = cells(re.search(rf"<tr>(?:(?!</tr>).)*{SLUG[p]}(?:(?!</tr>).)*</tr>", summ, re.S).group(0))
    ok([round(x, 2) for x in c] == [r["own_kc"], r["empty_kc"], r["fixed_kc"], r["total_kc"]], f"{p}: summary row {c}")
foot = cells(re.search(r"<tfoot>.*?</tfoot>", summ, re.S).group(0))
ok(eq(sum(foot[:3]), foot[3]) and eq(foot[3], total), f"summary footer {foot} adds up to invoice")
ok(all(f'href="/vyuctovani/sucha/2026/{s}"' in page for s in SLUG.values()), "links to all branch pages")

print("branch pages")
for p, r in rows.items():
    b = open(os.path.join(DATA, f"vyuctovani-sucha-2026-{SLUG[p]}.html")).read()
    out = [num(x) for x in re.findall(r'<span class="n[^"]*">(.*?)</span>', section(b, 'class="outcome"', "</section>"))]
    ok(eq(out[0], r["advances_kc"]) and eq(out[1], r["total_kc"]) and eq(out[2], abs(r["balance_kc"])), f"{p}: outcome {out}")
    comp = [cells(tr) for tr in re.findall(r"<tr>.*?</tr>", section(b, "<h2>Z čeho se podíl skládá</h2>"), re.S) if "<td" in tr]
    ok(eq(comp[0][1], r["own_kc"]) and eq(comp[1][1], r["empty_kc"]) and eq(comp[2][1], r["fixed_kc"]) and eq(comp[3][1], r["total_kc"]),
       f"{p}: composition {[c[-1] for c in comp]}")
    mem = [m for m in OUT["members"] if m["payer"] == p]
    for mode in ("sep", "fold", "even"):
        body = section(b, f'<tbody class="{mode}"', "</tbody>")
        trs = [cells(tr) for tr in re.findall(r"<tr[ >].*?</tr>", body, re.S)]
        member_trs = trs[:len(mem)]
        ok(eq(sum(t[2] for t in member_trs), sum(m["kwh"] for m in mem)), f"{p}/{mode}: member kWh as in out.json")
        if mode == "sep":
            ok(eq(sum(t[4] for t in member_trs), r["own_kc"]), f"{p}/sep: members sum to direct {r['own_kc']}")
            ok(eq(sum(t[4] for t in member_trs) + r["empty_kc"] + r["fixed_kc"], r["total_kc"]), f"{p}/sep: + empty + fixed = total")
        if mode == "fold":
            ok(eq(sum(t[4] for t in member_trs), r["total_kc"]), f"{p}/fold: members sum to total {r['total_kc']}")
            rates = [t[4] / t[2] / (m["kc"] / m["kwh"]) for t, m in zip(member_trs, mem)]
            ok(max(rates) - min(rates) < 0.01, f"{p}/fold: every member's price scaled by the same factor ({rates[0]:.3f})")
        if mode == "even":
            tot = [num(x) for x in re.findall(r'class="kc">(.*?)</span>', body)]
            ok(eq(sum(tot), r["total_kc"]), f"{p}/even (all ticked): members sum to total")
    led = section(b, '<table class="ledger">')
    mine = sum(num(x.split("·")[1]) for x in re.findall(r"<li>.*?<span class='n'>(.*?)</span>", led))
    ok(abs(mine - r["own_kc"]) < 0.05 * len(re.findall(r"<li>", led)), f"{p}: own ledger lines {mine:.2f} ≈ direct {r['own_kc']}")

print("even split in the browser (every combination of ticked members)")
JS = """<script>(function(){var cb=[].slice.call(document.querySelectorAll('tbody.even input')),res=[];
for(var mask=0;mask<(1<<cb.length);mask++){cb.forEach(function(c,i){c.checked=!!(mask&(1<<i))});
cb[0].dispatchEvent(new Event('change',{bubbles:true}));
var sum=0;document.querySelectorAll('tbody.even .kc').forEach(function(e){sum+=Math.round(parseFloat(e.textContent.replace(/\\s|\\u00a0/g,'').replace(',','.'))*100)});
var shares=[].map.call(document.querySelectorAll('tbody.even .share'),function(e){return e.textContent});
res.push(mask+':'+sum+':'+shares.join('|'))}
var d=document.createElement('pre');d.id='RES';d.textContent=res.join('\\n');document.body.appendChild(d)})()</script></body>"""
if os.path.exists(CHROME):
    for p, r in rows.items():
        b = open(os.path.join(DATA, f"vyuctovani-sucha-2026-{SLUG[p]}.html")).read().replace("</body>", JS)
        with tempfile.NamedTemporaryFile("w", suffix=".html", delete=False) as f:
            f.write(b)
        dom = subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--dump-dom", "file://" + f.name],
                             capture_output=True, text=True, timeout=60).stdout
        os.unlink(f.name)
        res = re.search(r'<pre id="RES">(.*?)</pre>', dom, re.S).group(1).split("\n")
        shared = round((r["fixed_kc"] + r["empty_kc"]) * 100)
        bad = []
        for line in res:
            mask, cents, shares = line.split(":", 2)
            n = bin(int(mask)).count("1")
            if n == 0:
                continue   # nobody ticked: the page shows a warning instead
            if int(cents) != round(r["total_kc"] * 100):
                bad.append(line)
            vals = sorted({s for s, i in zip(shares.split("|"), range(99)) if int(mask) >> i & 1})
            if len(vals) > 2:
                bad.append(line)   # shares must be equal (± 1 haléř)
        ok(not bad and len(res) == 2 ** len([m for m in OUT["members"] if m["payer"] == p]),
           f"{p}: {len(res) - 1} combinations sum to {r['total_kc']}, shares equal ±1 haléř" + (f" BAD {bad[:3]}" if bad else ""))
else:
    print("  skip (no Chrome)")

print("\nALL OK" if not fails else f"\n{len(fails)} FAILED")
raise SystemExit(1 if fails else 0)
