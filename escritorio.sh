#!/usr/bin/env bash
# CI-E1: la tanda de escritorio, las pruebas de la ventana de Electron de Paseo en Windows (pc/app/packages/desktop/e2e).
# Ninguna tanda de correr.sh las pasa. Va en la máquina extra que fuente-pc.sh añade cuando el plan trae "escr ... w".
# Uso: escritorio.sh <carpeta del paquete abierto> <carpeta de resultados>. Corre el código probado y no recibe ninguna clave.
# Todo va a archivos de la carpeta de resultados, que salen cifrados: nada del código probado sale en claro en el registro.
set -u
w=$1; o=$2
solo_enlaces() { ! grep -v -i -e "symlink" -e "Exiting with failure status" "$1" | grep -q .; }
mkdir -p "$w/src" "$o" && { tar -xzf "$w/src.tgz" -C "$w/src" 2> "$o/tar.log" || solo_enlaces "$o/tar.log"; } && rm -f "$w/src.tgz" && cd "$w/src/pc/app" || exit 1
# dev-runner.mjs pregunta a git la rama, y el "prepare" de Paseo instala lefthook: los dos necesitan un repositorio.
git init -q "$w/src"
case $(uname -s) in MINGW*|MSYS*|CYGWIN*) mkdir -p "$w/bin" && cp "$(cygpath -u "$SYSTEMROOT")/System32/tar.exe" "$w/bin/" && export PATH="$w/bin:$PATH" ;; esac
echo "escv 0 1 w" > "$o/tanda.txt"; cp "$w/ci/rama.txt" "$o/" 2>/dev/null
O=$(cygpath -m "$o" 2>/dev/null || echo "$o")
export LEFTHOOK=0 CI=true
# Cada prueba con su tope: si la ventana se queda colgada, el paso falla y la máquina deja su resumen igualmente.
paso() { local nombre=$1; shift; local s=$(date +%s); "$@" > "$o/$nombre.log" 2>&1; local c=$?; echo "$nombre $c $(( $(date +%s) - s ))" >> "$o/pasos.txt"; return $c; }
d=--workspace=@getpaseo/desktop
if paso instalar node scripts/npm-retry.mjs ci; then
  paso servidor npm run build:server
  paso electron node node_modules/electron/install.js
  # La del foco de Paseo 4679 vive en browser-tabs; Paseo solo la pasa en Linux.
  PASEO_DESKTOP_BROWSER_E2E_ARTIFACT_DIR="$O/pestanas" paso pestanas timeout 1200 npm run test:e2e:browser-tabs $d
  paso arranque timeout 600 npm run test:e2e:window-startup $d
  paso vida timeout 600 npm run test:e2e:lifecycle $d
  # test:e2e:renderer no va aquí: no abre la ventana sino Chromium, y Paseo solo la pasa en Linux. En Windows fallan
  # nueve pruebas suyas (pasada 45373647851).
fi
# Resumen como el de correr.sh. Cada paso que falla deja un fallo con su última línea de error, y otro por cada registro de
# los procesos que arranca la prueba, para que el veredicto diga qué pasó sin bajar los resultados. En sueltos.txt se apunta
# como "escritorio > <paso>".
node - "$O" <<'JS'
const fs = require('node:fs'), path = require('node:path');
const o = process.argv[2];
const pasos = fs.readFileSync(path.join(o, 'pasos.txt'), 'utf8').trim().split('\n').map(l => { const [n, code, s] = l.split(' '); return { n, code, s }; });
const leer = (f) => { try { return fs.readFileSync(f, 'utf8').replace(/\x1b\[[0-9;]*m/g, '').split(/\r?\n/).map(l => l.trim()).filter(Boolean); } catch { return []; } };
// La última línea de error que no sea el aviso final de npm ni un aviso suelto.
const ultimo = (lineas, solo) => {
  const util = lineas.filter(l => !/^npm (error|ERR!)|WARN/i.test(l)).reverse();
  return util.find(l => /^(\[\w+\] )?\w*Error\b[^:]*:|failed to start|exited with/.test(l)) || util.find(l => /error|failed|timed? ?out|assert/i.test(l)) || (solo ? null : util[0]);
};
const fallos = [];
for (const p of pasos.filter(p => p.code !== '0')) {
  const lineas = leer(path.join(o, `${p.n}.log`));
  fallos.push({ t: `escritorio > ${p.n}: ${(ultimo(lineas) || `salió con ${p.code}`).slice(0, 200)}`, m: lineas.slice(-40).join('\n').slice(0, 2000) });
  // Los registros de la ventana y del servidor que arranca la prueba, en <carpeta del paso>/*.log.
  const dir = path.join(o, p.n);
  for (const f of fs.existsSync(dir) ? fs.readdirSync(dir).filter(f => f.endsWith('.log')) : []) {
    const e = ultimo(leer(path.join(dir, f)).slice(-200), true);
    if (e) fallos.push({ t: `escritorio > ${p.n}/${f}: ${e.slice(0, 200)}`, m: '' });
  }
}
fs.writeFileSync(path.join(o, 'resumen.json'), JSON.stringify({ pasos, tests: 0, fallos }));
if (fallos.length) fs.writeFileSync(path.join(o, 'mal'), '');
JS
