# Uso: python -X utf8 pc/ci/puerta.py <pasada nueva> <pasada base>
# Compara todos los grupos de una completa con la base: pantallas, piezas, formato, revisor y
# los demás pasos. Un fallo cuenta como conocido si está en la base o en pc/fabrica/sueltos.txt.
# Dice SÍ o NO al final. Solo se sube a main con SÍ.
# La nube lo calcula igual en el trabajo "veredicto" de pc.yml (CI-V1), con una copia idéntica en pc/ci/publico/puerta.py.
#   python -X utf8 pc/ci/puerta.py --json <pasada>   vuelca la pasada en JSON: así se hace el resumen base (publico/base-pc.enc).
#   La base puede ser ese JSON en vez de un número de pasada. DUENDI_SUELTOS cambia la lista de fallos conocidos.
import glob, json, os, re, sys

CI = os.environ.get("DUENDI_CI", "C:/Users/HP/duendi-herramientas/ci-pc")
SUELTOS = os.environ.get("DUENDI_SUELTOS") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "fabrica", "sueltos.txt")
ANSI = re.compile(r"\x1b\[[0-9;]*m")
FALLA = re.compile(r"^\s+(\d+) failed\s*$")
E2E = re.compile(r"^\s+\[browser\] › (\S+?:\d+):\d+ › ")


def e2e_fallos(path):
    out, dentro = set(), False
    for raw in open(path, encoding="utf-8", errors="replace"):
        linea = ANSI.sub("", raw.rstrip("\n"))
        if FALLA.match(linea):
            dentro = True
            continue
        if dentro:
            m = E2E.match(linea)
            if m:
                out.add("app/" + m.group(1))
            else:
                dentro = False
    return out


def leer(run):
    if run.endswith(".json"):
        return {t: (ok, set(p), set(f)) for t, (ok, p, f) in json.load(open(run, encoding="utf-8")).items()}
    raiz = f"{CI}/run{run}"
    if not os.path.isdir(raiz):
        sys.exit(f"No encuentro {raiz}")
    maquinas = {}
    for d in sorted(glob.glob(raiz + "/t*")):
        try:
            tanda = open(d + "/tanda.txt", encoding="utf-8").read().strip()
        except OSError:
            continue
        pasos, fallos, ok = set(), set(), True
        try:
            j = json.load(open(d + "/resumen.json", encoding="utf-8"))
            pasos = {p["n"] for p in j.get("pasos", []) if str(p.get("code")) != "0"}
            for f in j.get("fallos", []):
                fallos.add(f.get("t", str(f)) if isinstance(f, dict) else str(f))
        except (OSError, ValueError):
            ok = False
        if os.path.exists(d + "/e2e.log"):
            fallos |= e2e_fallos(d + "/e2e.log")
        maquinas[tanda] = (ok, pasos, fallos)
    return maquinas


def cargar_sueltos():
    out = []
    for linea in open(SUELTOS, encoding="utf-8"):
        linea = linea.strip()
        if not linea or linea.startswith("#"):
            continue
        clave = re.sub(r"\s+(siempre|a ratos)\s+\S+$", "", linea)
        out.append(clave)
    return out


def conocido(fallo, sueltos, base):
    if fallo in base:
        return True
    for s in sueltos:
        if s == fallo:
            return True
        if " > " in s:
            archivo, nombre = s.split(" > ", 1)
            if fallo.startswith(os.path.basename(archivo) + " > ") and nombre in fallo:
                return True
    return False


if sys.argv[1] == "--json":
    print(json.dumps({t: [ok, sorted(p), sorted(f)] for t, (ok, p, f) in leer(sys.argv[2]).items()}, ensure_ascii=False))
    sys.exit(0)
nueva, base = leer(sys.argv[1]), leer(sys.argv[2])
sueltos = cargar_sueltos()
fallos_base = set().union(*(m[2] for m in base.values())) if base else set()
motivos = []
grupo = lambda t: (t.split()[0], t.split()[-1])  # el reparto en máquinas puede cambiar
for g in sorted({grupo(t) for t in base} - {grupo(t) for t in nueva}):
    motivos.append(f"{' '.join(g)}: grupo que falta en la nueva")
for tanda, (ok, pasos, fallos) in sorted(nueva.items()):
    if not ok:
        motivos.append(f"{tanda}: sin resumen.json")
        continue
    nuevos = sorted(f for f in fallos if not conocido(f, sueltos, fallos_base))
    for f in nuevos:
        motivos.append(f"{tanda}: fallo nuevo: {f[:160]}")
    pasos_base = base.get(tanda, (True, set(), set()))[1]
    for p in sorted(pasos - pasos_base):
        if not fallos or nuevos:
            motivos.append(f"{tanda}: paso {p} falla y no en la base")
for m in motivos:
    print(m)
print("SÍ" if not motivos else f"NO ({len(motivos)} motivos)")
sys.exit(0 if not motivos else 1)
