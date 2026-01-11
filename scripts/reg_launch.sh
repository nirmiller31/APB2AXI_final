#!/usr/bin/env bash
# run command: bash scripts/reg_launch.sh (from Project), dont forget to clean regression!!!
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJ_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"

# ---------------------------
# User inputs (edit defaults)
# ---------------------------
UVM_TESTNAME="${UVM_TESTNAME:-apb2axi_test}"

# Which tests to run: all|read|write|e2e|error
TEST_SET="${TEST_SET:-all}"

# Seeds: either provide SEEDS="1 2 3" or SEED_MODE + ranges
SEEDS="${SEEDS:-}"

# Seed generation mode: "inc" or "rand"
SEED_MODE="${SEED_MODE:-rand}"

# Random seed range (only used when SEED_MODE=rand)
SEED_RAND_MIN="${SEED_RAND_MIN:-1}"
SEED_RAND_MAX="${SEED_RAND_MAX:-2147483647}"

# Incremental mode params (only used when SEED_MODE=inc)
SEED_START="${SEED_START:-777225}"
SEED_COUNT="${SEED_COUNT:-10}"

# Parallelism
JOBS="${JOBS:-1}"

# Where simv lives (or build step below can create it)
SIMV="${SIMV:-$PROJ_DIR/simv}"

# Output dir
OUTROOT="${OUTROOT:-out/regress_${UVM_TESTNAME}_$(date +%Y%m%d_%H%M%S)}"

# Live report refresh during regression (seconds)
REPORT_REFRESH_SEC="${REPORT_REFRESH_SEC:-5}"

# ---------------------------
# Define MODES (name + flags)
# Each mode is: MODE_NAME|EXTRA_PLUSARGS
# ---------------------------
READ_MODES=(
  "read_regular_outstanding|+APB2AXI_SEQ=READ"
  "read_linear_outstanding|+APB2AXI_SEQ=READ +LINEAR_OUTSTANDING"
  "read_extreme_outstanding|+APB2AXI_SEQ=READ +EXTREME_OUTSTANDING"
)

WRITE_MODES=(
  "write_regular_outstanding|+APB2AXI_SEQ=WRITE"
  "write_linear_outstanding|+APB2AXI_SEQ=WRITE +LINEAR_OUTSTANDING"
  "write_extreme_outstanding|+APB2AXI_SEQ=WRITE +EXTREME_OUTSTANDING"
)

E2E_MODES=(
  "e2e_regular_outstanding|+APB2AXI_SEQ=E2E"
  "e2e_linear_outstanding|+APB2AXI_SEQ=E2E +LINEAR_OUTSTANDING"
  "e2e_extreme_outstanding|+APB2AXI_SEQ=E2E +EXTREME_OUTSTANDING"
)

ERROR_MODES=(
  "read_error|+APB2AXI_SEQ=READ_ERROR"
  "write_error|+APB2AXI_SEQ=WRITE_ERROR"
  "read_error_worst_policy|+APB2AXI_SEQ=READ_ERROR +RESP_POLICY_WORST"
)

case "$TEST_SET" in
  all)   MODES=( "${READ_MODES[@]}" "${WRITE_MODES[@]}" "${E2E_MODES[@]}") ;;
  read)  MODES=( "${READ_MODES[@]}" ) ;;
  write) MODES=( "${WRITE_MODES[@]}" ) ;;
  e2e)   MODES=( "${E2E_MODES[@]}" ) ;;
  error) MODES=( "${ERROR_MODES[@]}" ) ;;
  *)
    echo "[ERROR] Unknown TEST_SET='$TEST_SET' (use: all|read|write|e2e|error)" >&2
    exit 2
    ;;
esac

# ---------------------------
# Helper: build seeds list
# ---------------------------
if [[ -z "$SEEDS" ]]; then
  if [[ "$SEED_MODE" == "rand" ]]; then
    # Generate SEED_COUNT random seeds in [SEED_RAND_MIN, SEED_RAND_MAX]
    SEEDS="$(python3 - <<'PY'
import os, random
n  = int(os.environ.get("SEED_COUNT","10"))
lo = int(os.environ.get("SEED_RAND_MIN","1"))
hi = int(os.environ.get("SEED_RAND_MAX","2147483647"))
if lo > hi:
    lo, hi = hi, lo
span = hi - lo + 1
unique = (span >= n)
rnd = random.SystemRandom()
seen = set()
out = []
while len(out) < n:
    x = rnd.randrange(lo, hi+1)
    if unique and x in seen:
        continue
    seen.add(x)
    out.append(str(x))
print(" ".join(out))
PY
)"
  else
    # Incremental (original behavior)
    SEEDS=""
    for ((s=SEED_START; s<SEED_START+SEED_COUNT; s++)); do
      SEEDS+="$s "
    done
  fi
fi

mkdir -p "$OUTROOT"/{runs,logs}
STATUS_CSV="$OUTROOT/status.csv"
SUMMARY_TXT="$OUTROOT/summary.txt"
SUMMARY_HTML="$OUTROOT/summary.html"

echo "mode,seed,status,dir,log" > "$STATUS_CSV"
: > "$SUMMARY_TXT"

# Helpful "latest" pointer for quick GUI serving
mkdir -p "$PROJ_DIR/out"
ln -sfn "$(realpath "$OUTROOT")" "$PROJ_DIR/out/latest"

# ---------------------------
# Optional build step (uncomment if you want)
# ---------------------------
# if [[ ! -x "$SIMV" ]]; then
#   echo "[BUILD] simv not found. Building..."
#   vcs -full64 -sverilog -timescale=1ns/1ps -l "$OUTROOT/comp.log" \
#       -debug_access+all -kdb -f filelist.f
# fi

# ---------------------------
# Run one job
# ---------------------------
run_one() {
  local mode_name="$1"
  local mode_args="$2"
  local seed="$3"

  local rundir="$OUTROOT/runs/${mode_name}/seed_${seed}"
  local logfile="$rundir/sim.log"
  mkdir -p "$rundir"

  # Mark running
  echo "${mode_name},${seed},RUNNING,${rundir},${logfile}" >> "$STATUS_CSV"

  # Run
  (
     cd "$rundir"
     echo "[CMD] $SIMV +UVM_TESTNAME=$UVM_TESTNAME +ntb_random_seed=$seed -l sim.log $mode_args" > cmdline.txt
     "$SIMV" \
       +UVM_TESTNAME="$UVM_TESTNAME" \
       +ntb_random_seed="$seed" \
       -l sim.log \
       $mode_args
  ) || true

  # Decide PASS/FAIL
  local status="PASS"

  if [[ ! -f "$logfile" ]]; then
    status="FAIL"
  else
    if grep -Eq "UVM_ERROR\s*:\s*[1-9]|UVM_FATAL\s*:\s*[1-9]" "$logfile"; then
      status="FAIL"
    fi
  fi

  echo "[$status] mode=$mode_name seed=$seed  log=$logfile" >> "$SUMMARY_TXT"

  # Append final status row
  echo "${mode_name},${seed},${status},${rundir},${logfile}" >> "$STATUS_CSV"
}

export -f run_one
export UVM_TESTNAME SIMV OUTROOT STATUS_CSV SUMMARY_TXT

# ---------------------------
# Launch all (parallel)
# ---------------------------
echo "[INFO] OUTROOT=$OUTROOT"
echo "[INFO] TEST=$UVM_TESTNAME"
echo "[INFO] TEST_SET=$TEST_SET"
echo "[INFO] MODES=${#MODES[@]}  SEEDS=($SEEDS)"
echo "[INFO] Latest pointer: $PROJ_DIR/out/latest"
echo

jobs_file="$OUTROOT/jobs.list"
: > "$jobs_file"

# Encode/decode helper (no external deps beyond python3)
b64enc() { python3 - <<'PY' "$1"
import base64, sys
print(base64.b64encode(sys.argv[1].encode()).decode())
PY
}

b64dec() { python3 - <<'PY' "$1"
import base64, sys
print(base64.b64decode(sys.argv[1]).decode())
PY
}

# Build jobs as 3 safe tokens: mode_name seed mode_args_b64
for m in "${MODES[@]}"; do
  mode_name="${m%%|*}"
  mode_args="${m#*|}"
  mode_b64="$(b64enc "$mode_args")"
  for seed in $SEEDS; do
    printf "%s %s %s\n" "$mode_name" "$seed" "$mode_b64" >> "$jobs_file"
  done
done

worker() {
  local mode_name="$1"
  local seed="$2"
  local mode_b64="$3"
  local mode_args
  mode_args="$(b64dec "$mode_b64")"
  run_one "$mode_name" "$mode_args" "$seed"
}

export -f worker b64dec

# ---------------------------
# HTML generator (Firefox/Chrome compatible)
# (ES5-only JS; UTF-8 output; no fancy unicode required)
# ---------------------------
export STATUS_CSV SUMMARY_HTML

regen_html() {
  python3 - <<'PY'
import csv, html, os, time

outroot = os.environ["OUTROOT"]
status_csv = os.environ["STATUS_CSV"]
summary_html = os.environ["SUMMARY_HTML"]

rows=[]
try:
    with open(status_csv, newline="") as f:
        r=csv.reader(f)
        next(r, None)
        for row in r:
            if len(row) == 5:
                rows.append(row)
except FileNotFoundError:
    rows=[]

# Keep last status per (mode,seed)
last={}
for mode,seed,status,dir_,log in rows:
    last[(mode,seed)] = (status,dir_,log)

items=[(k[0], int(k[1]), *v) for k,v in last.items() if v[0] in ("PASS","FAIL","RUNNING")]
items.sort(key=lambda x:(x[0], x[1]))

def relpath(p):
    try:
        return os.path.relpath(p, outroot)
    except Exception:
        return p

counts={"PASS":0,"FAIL":0,"RUNNING":0}
for _,_,st,_,_ in items:
    counts[st]=counts.get(st,0)+1

total=len(items)
done = counts.get("PASS",0) + counts.get("FAIL",0)
running = counts.get("RUNNING",0)
pct = 0 if total == 0 else int(round(100.0 * done / total))
gen_time=time.strftime("%Y-%m-%d %H:%M:%S")

css = r"""
:root{
  --bg:#0b1020;
  --panel:#0f1730;
  --card:#111b38;
  --text:#e8ecff;
  --muted:#a9b3d6;
  --border: rgba(255,255,255,.10);
  --shadow: 0 10px 30px rgba(0,0,0,.35);
  --pass:#2ecc71;
  --fail:#ff5c5c;
  --run:#f6c343;
  --accent:#7c5cff;
}
[data-theme="light"]{
  --bg:#f6f7fb;
  --panel:#ffffff;
  --card:#ffffff;
  --text:#131a33;
  --muted:#556087;
  --border: rgba(17,26,51,.12);
  --shadow: 0 10px 25px rgba(17,26,51,.12);
  --pass:#1fa764;
  --fail:#e63946;
  --run:#f2b705;
  --accent:#5b5cff;
}

*{box-sizing:border-box}
body{
  margin:0;
  font-family: ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Helvetica, Arial;
  background: radial-gradient(1200px 800px at 20% 0%, rgba(124,92,255,.22), transparent 60%),
              radial-gradient(1000px 700px at 90% 10%, rgba(46,204,113,.12), transparent 55%),
              var(--bg);
  color:var(--text);
}
a{color:var(--text); text-decoration:none}
a:hover{text-decoration:underline}

header{
  position:sticky; top:0; z-index:10;
  background: linear-gradient(to bottom, rgba(15,23,48,.92), rgba(15,23,48,.72));
  border-bottom: 1px solid var(--border);
}
.wrap{max-width:1200px; margin:0 auto; padding:18px 20px}

.projectHeader{ text-align:center; margin-bottom: 12px; }
.projectHeader .names{
  font-size: 34px;
  font-weight: 800;
  letter-spacing: 0.6px;
  background: linear-gradient(90deg, var(--accent), var(--pass));
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
}
.projectHeader .project{
  margin-top: 6px;
  font-size: 20px;
  font-weight: 700;
  color: var(--text);
  opacity: 0.95;
}

.title{
  display:flex; gap:14px; align-items:flex-start; justify-content:space-between; flex-wrap:wrap;
}
h1{margin:0; font-size:22px; letter-spacing:.2px}
.sub{color:var(--muted); font-size:13px; margin-top:6px}

.pills{display:flex; gap:10px; flex-wrap:wrap; align-items:center}
.pill{
  display:inline-flex; align-items:center; gap:8px;
  padding:8px 10px; border:1px solid var(--border); border-radius:999px;
  background: rgba(255,255,255,.04);
  box-shadow: var(--shadow);
  font-size:13px;
}
.dot{width:10px; height:10px; border-radius:50%}
.dot.pass{background:var(--pass)}
.dot.fail{background:var(--fail)}
.dot.run{background:var(--run)}
.pill strong{font-weight:700}

/* Progress bar */
.progressWrap{
  margin-top:14px;
  display:flex; gap:12px; align-items:center; flex-wrap:wrap;
}
.progressBar{
  flex: 1 1 420px;
  height: 14px;
  border-radius: 999px;
  border: 1px solid var(--border);
  background: rgba(255,255,255,.04);
  overflow:hidden;
  box-shadow: var(--shadow);
}
.progressFill{
  height:100%;
  width: 0%;
  border-radius:999px;
  background: linear-gradient(90deg, var(--accent), var(--pass));
}
.progressMeta{
  display:flex; gap:10px; align-items:center; flex-wrap:wrap;
  color: var(--muted);
  font-size: 13px;
}
.progressMeta b{color: var(--text);}
.progressTag{
  display:inline-flex; align-items:center; gap:8px;
  padding:6px 10px; border:1px solid var(--border);
  border-radius: 999px;
  background: rgba(255,255,255,.04);
}

.controls{
  margin-top:14px;
  display:flex; gap:10px; flex-wrap:wrap; align-items:center; justify-content:space-between;
}
.leftControls{display:flex; gap:10px; flex-wrap:wrap; align-items:center}
.ctrl{
  background: rgba(255,255,255,.04);
  border:1px solid var(--border);
  color:var(--text);
  padding:10px 12px;
  border-radius:12px;
  outline:none;
}
input.ctrl{min-width:260px}
select.ctrl{min-width:160px}
button.ctrl{cursor:pointer}
button.ctrl:hover{border-color: rgba(124,92,255,.55)}

main .wrap{padding-top:14px; padding-bottom:40px}

.tableCard{
  background: linear-gradient(180deg, rgba(255,255,255,.04), rgba(255,255,255,.02));
  border:1px solid var(--border);
  border-radius:18px;
  box-shadow: var(--shadow);
  overflow:hidden;
}
table{width:100%; border-collapse:collapse}
th, td{padding:12px 12px; border-bottom:1px solid var(--border); font-size:13px}
th{
  text-align:left;
  color:var(--muted);
  background: rgba(0,0,0,.12);
  cursor:pointer;
  user-select:none;
}
th .arrow{opacity:.6; margin-left:6px}

/* Full-row coloring by status */
tbody tr[data-status="PASS"] td    { background: rgba(46,204,113,.10); }
tbody tr[data-status="FAIL"] td    { background: rgba(255,92,92,.12); }
tbody tr[data-status="RUNNING"] td { background: rgba(246,195,67,.12); }
tbody tr:hover td{background: rgba(124,92,255,.12) !important;}

.badge{
  display:inline-flex; align-items:center; gap:8px;
  padding:6px 10px; border-radius:999px; font-weight:700;
  border:1px solid var(--border);
}
.badge.PASS{background: rgba(46,204,113,.16)}
.badge.FAIL{background: rgba(255,92,92,.16)}
.badge.RUNNING{background: rgba(246,195,67,.16)}
.badge .dot{width:8px; height:8px}

.mono{font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", monospace}
.small{font-size:12px; color:var(--muted)}
.right{display:flex; gap:10px; align-items:center; flex-wrap:wrap}
kbd{
  background: rgba(255,255,255,.06);
  border:1px solid var(--border);
  border-bottom-width:2px;
  padding:2px 6px;
  border-radius:8px;
  font-size:12px;
}
footer{color:var(--muted); font-size:12px; margin-top:14px}
"""

# ES5-only JS (ancient Firefox compatible)
js = r"""
function qs(s){ return document.querySelector(s); }
function qsa(s){
  var n = document.querySelectorAll(s);
  return Array.prototype.slice.call(n);
}

var sortKey = "mode";
var sortDir = 1;

function getAttr(tr, name){
  var v = tr.getAttribute(name);
  if (v !== null && v !== undefined) return v;
  if (tr.dataset){
    var k = name.replace(/^data-/, "").replace(/-([a-z])/g, function(_,c){ return c.toUpperCase(); });
    return tr.dataset[k];
  }
  return "";
}

function getRows(){
  var trs = qsa("tbody tr");
  var rows = [];
  for (var i=0; i<trs.length; i++){
    var tr = trs[i];
    rows.push({
      tr: tr,
      mode: getAttr(tr, "data-mode") || "",
      seed: parseInt(getAttr(tr, "data-seed") || "0", 10),
      status: getAttr(tr, "data-status") || "",
      log: getAttr(tr, "data-log") || ""
    });
  }
  return rows;
}

function applyFilters(){
  var searchEl = qs("#search");
  var statusEl = qs("#statusFilter");
  var hideEl   = qs("#hidePass");

  var query = (searchEl && searchEl.value ? searchEl.value : "").replace(/^\s+|\s+$/g,"").toLowerCase();
  var st = statusEl ? statusEl.value : "ALL";
  var hidePass = hideEl ? !!hideEl.checked : false;

  var rows = getRows();
  var shown = 0;

  for (var i=0; i<rows.length; i++){
    var r = rows[i];
    var hay = (r.mode + " " + r.seed + " " + r.status + " " + r.log).toLowerCase();
    var ok = true;

    if (query && hay.indexOf(query) === -1) ok = false;
    if (st !== "ALL" && r.status !== st) ok = false;
    if (hidePass && r.status === "PASS") ok = false;

    r.tr.style.display = ok ? "" : "none";
    if (ok) shown++;
  }

  var shownEl = qs("#shownCount");
  if (shownEl) shownEl.innerHTML = "" + shown;
}

function clearArrows(){
  var ths = qsa("th");
  for (var i=0; i<ths.length; i++){
    var a = ths[i].querySelector(".arrow");
    if (a) ths[i].removeChild(a);
  }
}

function setArrow(key){
  var ths = qsa('th[data-key]');
  var th = null;
  for (var i=0; i<ths.length; i++){
    if (ths[i].getAttribute("data-key") === key){ th = ths[i]; break; }
  }
  if (!th) return;
  var sp = document.createElement("span");
  sp.className = "arrow";
  sp.innerHTML = (sortDir === 1) ? "▲" : "▼";
  th.appendChild(sp);
}

function statusPri(s){
  if (s === "FAIL") return 0;
  if (s === "RUNNING") return 1;
  return 2;
}

function sortRows(key){
  if (sortKey === key) sortDir *= -1;
  else { sortKey = key; sortDir = 1; }

  var tbody = qs("tbody");
  if (!tbody) return;

  var rows = getRows();
  rows.sort(function(a,b){
    var va = a[key], vb = b[key];
    if (key === "status"){
      va = statusPri(a.status);
      vb = statusPri(b.status);
    }
    if (va < vb) return -1*sortDir;
    if (va > vb) return  1*sortDir;
    return 0;
  });

  for (var i=0; i<rows.length; i++){
    tbody.appendChild(rows[i].tr);
  }

  clearArrows();
  setArrow(key);
}

var autoTimer = null;
function setAutoRefresh(on){
  var sel = qs("#refreshSec");
  var sec = sel ? parseInt(sel.value || "5", 10) : 5;
  if (autoTimer) { clearInterval(autoTimer); autoTimer = null; }
  if (on){
    autoTimer = setInterval(function(){ location.reload(); }, Math.max(3,sec)*1000);
  }
}

function safeGetLS(k){
  try { return window.localStorage ? localStorage.getItem(k) : null; } catch(e){ return null; }
}
function safeSetLS(k,v){
  try { if (window.localStorage) localStorage.setItem(k,v); } catch(e){}
}

function toggleTheme(){
  var root = document.documentElement;
  var cur = root.getAttribute("data-theme") || "dark";
  var next = (cur === "dark") ? "light" : "dark";
  root.setAttribute("data-theme", next);
  safeSetLS("reg_theme", next);
}

function bind(el, ev, fn){
  if (!el) return;
  el.addEventListener(ev, fn, false);
}

window.addEventListener("DOMContentLoaded", function(){
  var saved = safeGetLS("reg_theme");
  if (saved) document.documentElement.setAttribute("data-theme", saved);

  var pctEl = qs("#pct");
  var fillEl = qs("#fill");
  if (pctEl && fillEl){
    var pct = parseInt(pctEl.getAttribute("data-pct") || "0", 10);
    fillEl.style.width = pct + "%";
  }

  var runningFlag = pctEl ? (pctEl.getAttribute("data-running") || "0") : "0";
  if (runningFlag === "1"){
    var ar = qs("#autoRefresh");
    if (ar) ar.checked = true;
    setAutoRefresh(true);
  }

  bind(qs("#search"), "input", applyFilters);
  bind(qs("#statusFilter"), "change", applyFilters);
  bind(qs("#hidePass"), "change", applyFilters);

  var heads = qsa('th[data-key]');
  for (var i=0; i<heads.length; i++){
    (function(th){
      bind(th, "click", function(){
        sortRows(th.getAttribute("data-key"));
      });
    })(heads[i]);
  }

  bind(qs("#themeBtn"), "click", toggleTheme);

  var auto = qs("#autoRefresh");
  bind(auto, "change", function(){ setAutoRefresh(!!auto.checked); });

  var ref = qs("#refreshSec");
  bind(ref, "change", function(){
    if (auto && auto.checked) setAutoRefresh(true);
  });

  document.addEventListener("keydown", function(e){
    e = e || window.event;
    var k = e.key || e.keyCode;
    if (k === "/" || k === 191){
      if (e.preventDefault) e.preventDefault();
      var s = qs("#search");
      if (s) s.focus();
    }
  }, false);

  applyFilters();
  sortRows("mode");
}, false);
"""

auto_refresh_hint = "1" if running > 0 else "0"

with open(summary_html, "w", encoding="utf-8") as f:
    f.write("<!doctype html><html><head><meta charset='utf-8'>")
    f.write("<meta name='viewport' content='width=device-width, initial-scale=1'>")
    f.write("<title>Regression Summary</title>")
    f.write("<style>%s</style></head>" % css)
    f.write("<body>")

    f.write("<header><div class='wrap'>")
    f.write("<div class='projectHeader'>")
    f.write("<div class='names'>Nir Miller &amp; Ido Oreg</div>")
    f.write("<div class='project'>Project A</div>")
    f.write("</div>")

    f.write("<div class='title'>")
    f.write("<div>")
    f.write("<h1>Regression Summary</h1>")
    f.write("<div class='sub'>OUT: <span class='mono'>%s</span> &nbsp;|&nbsp; Generated: %s</div>" %
            (html.escape(outroot), html.escape(gen_time)))
    f.write("</div>")
    f.write("<div class='right'>")
    f.write("<button id='themeBtn' class='ctrl' title='Toggle theme'>Theme</button>")
    f.write("<span class='small'>Tip: press <kbd>/</kbd> to search</span>")
    f.write("</div>")
    f.write("</div>")  # title

    f.write("<div class='pills'>")
    f.write("<span class='pill'><span class='dot fail'></span><strong>FAIL</strong> %d</span>" % counts.get("FAIL",0))
    f.write("<span class='pill'><span class='dot run'></span><strong>RUNNING</strong> %d</span>" % counts.get("RUNNING",0))
    f.write("<span class='pill'><span class='dot pass'></span><strong>PASS</strong> %d</span>" % counts.get("PASS",0))
    f.write("<span class='pill'><span class='dot' style='background:var(--accent)'></span><strong>TOTAL</strong> %d</span>" % total)
    f.write("</div>")

    # Progress
    f.write("<div class='progressWrap'>")
    f.write("<div class='progressBar'><div class='progressFill' id='fill' style='width:%d%%;'></div></div>" % pct)
    f.write("<div class='progressMeta'>")
    f.write("<span class='progressTag'><b>Progress</b> <span id='pct' data-pct='%d' data-running='%s'>%d%%</span></span>" %
            (pct, auto_refresh_hint, pct))
    f.write("<span class='progressTag'><b>Done</b> %d/%d</span>" % (done, total))
    if running:
        f.write("<span class='progressTag'><b>Running</b> %d</span>" % running)
    f.write("</div></div>")

    # Controls
    f.write("<div class='controls'>")
    f.write("<div class='leftControls'>")
    f.write("<input id='search' class='ctrl' placeholder='Search (mode / seed / status / log)'>")
    f.write("<select id='statusFilter' class='ctrl'>")
    f.write("<option value='ALL'>All statuses</option>")
    for s in ("FAIL","RUNNING","PASS"):
        f.write("<option value='%s'>%s</option>" % (s,s))
    f.write("</select>")
    f.write("<label class='pill' style='box-shadow:none;background:transparent'>")
    f.write("<input id='hidePass' type='checkbox' style='transform:scale(1.1); margin-right:8px'> Hide PASS</label>")
    f.write("</div>")
    f.write("<div class='right'>")
    f.write("<label class='pill' style='box-shadow:none;background:transparent'>")
    f.write("<input id='autoRefresh' type='checkbox' style='transform:scale(1.1); margin-right:8px'> Auto refresh</label>")
    f.write("<select id='refreshSec' class='ctrl'>")
    for sec in (5,10,20,30,60):
        f.write("<option value='%d'>%ds</option>" % (sec, sec))
    f.write("</select>")
    f.write("<span class='small'>Shown: <span id='shownCount'>%d</span> / %d</span>" % (total, total))
    f.write("</div>")
    f.write("</div>")  # controls

    f.write("</div></header>")

    f.write("<main><div class='wrap'>")
    f.write("<div class='tableCard'>")
    f.write("<table>")
    f.write("<thead><tr>")
    f.write("<th data-key='mode'>Mode</th>")
    f.write("<th data-key='seed'>Seed</th>")
    f.write("<th data-key='status'>Status</th>")
    f.write("<th data-key='log'>Log</th>")
    f.write("</tr></thead><tbody>")

    for mode,seed,status,dir_,log in items:
        rel = relpath(log)
        badge = "<span class='badge %s'><span class='dot %s'></span>%s</span>" % (
            status, status.lower(), status
        )
        f.write("<tr data-mode='%s' data-seed='%d' data-status='%s' data-log='%s'>" %
                (html.escape(mode), seed, html.escape(status), html.escape(rel)))
        f.write("<td class='mono'>%s</td>" % html.escape(mode))
        f.write("<td class='mono'>%d</td>" % seed)
        f.write("<td>%s</td>" % badge)
        f.write("<td class='mono'><a href='%s'>%s</a></td>" % (html.escape(rel), html.escape(rel)))
        f.write("</tr>")

    f.write("</tbody></table></div>")
    f.write("<footer>Click a column header to sort. Use filters to narrow down failures quickly.</footer>")
    f.write("</div></main>")

    f.write("<script>%s</script>" % js)
    f.write("</body></html>")
PY
}

# ---------------------------
# Live HTML updater (full GUI during run)
# ---------------------------
(
  while true; do
    regen_html
    sleep "$REPORT_REFRESH_SEC"
  done
) &
UPDATER_PID=$!
trap 'kill $UPDATER_PID 2>/dev/null || true' EXIT

# ---------------------------
# Execute jobs
# ---------------------------
cat "$jobs_file" | xargs -P "$JOBS" -n 3 bash -lc 'worker "$0" "$1" "$2"'

# Stop live updater and write final report once
kill "$UPDATER_PID" 2>/dev/null || true
regen_html

# ---------------------------
# Helper: easy report launch
# ---------------------------
cat > "$OUTROOT/serve_report.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
echo "[INFO] Serving regression report at:"
echo "       http://localhost:8000/summary.html"
python3 -m http.server 8000
EOF
chmod +x "$OUTROOT/serve_report.sh"

echo
echo "[DONE] Text summary : $SUMMARY_TXT"
echo "[DONE] HTML summary : $SUMMARY_HTML"
echo "[TIP] To view the report:"
echo "      $OUTROOT/serve_report.sh"
echo "[TIP] Or serve 'latest' (always points to last regression):"
echo "      cd '$PROJ_DIR/out/latest' && python3 -m http.server 8000"