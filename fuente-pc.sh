#!/usr/bin/env bash
# Prepara el paquete cifrado de una pasada del programa de PC y dice qué máquinas hacen falta. No escribe nada legible:
# el código solo existe descifrado dentro de cada máquina, y lo que sale es la lista de máquinas y una huella.
#  - Lanzada a mano (A): el paquete ya viene cifrado desde el PC.
#  - Cada 10 minutos: si la carpeta pc/ de main cambió desde la última pasada, la prueba entera.
#    Si no, prueba una rama de trabajo que aún no se haya probado, sin montar la ventana.
#    La dirección del repositorio privado viene de un secreto, no de este archivo.
set -u
w=$RUNNER_TEMP/f; mkdir -p "$w"; cd "$w" || exit 1
R=$GITHUB_REPOSITORY
echo "m=[]" >> "$GITHUB_OUTPUT"

if [ -n "${A:-}" ]; then
  curl -sSfL -H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/octet-stream" "https://api.github.com/repos/$R/releases/assets/$A" -o p.enc || exit 1
  node "$GITHUB_WORKSPACE/cifra.cjs" d p.enc p.tar && tar -xf p.tar ci/plan.txt || exit 1
else
  install -m 600 /dev/null llave && printf '%s\n' "$LLAVE" > llave
  export GIT_SSH_COMMAND="ssh -i $w/llave -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
  U=$RUTA_PRIVADA
  hechas=$(gh cache list -R "$R" -L 1000 --key pc- --json key -q '.[].key')
  huella() { printf '%s%s' "$CLAVE" "$1" | sha256sum | cut -c1-20; }
  git clone -q --depth 1 --filter=blob:none --no-checkout "$U" r || exit 1
  # El reparto sale siempre del plan.py de main: el de una rama fabrica/* no se ejecuta aquí, donde están las claves.
  git -C r show HEAD:pc/ci/plan.py > "$w/plan.py" || exit 1
  # Huella de pc/app, pc/ci y el código de pc/fabrica, que prueba la tanda de tipos, mezclada con la clave: dice si ya se
  # probó sin decir qué hay dentro. Las notas de la fábrica cambian a cada rato y no cuentan.
  k=pc-$(huella "$({ git -C r rev-parse HEAD:pc/app HEAD:pc/ci; git -C r ls-tree -r HEAD pc/fabrica/ | awk '$4 ~ /\.mjs$/ {print $3}'; } | tr -d '\n')")
  rama=main; modo=completa
  if [ -n "${B:-}" ]; then
    # Una rama pedida a mano (lanzar.cjs --rama): se baja de GitHub y el PC no empaqueta. El reparto sigue saliendo
    # del plan.py de main. Solo nombres de rama normales y los modos que no necesitan nada del PC.
    [[ "$B" =~ ^[A-Za-z0-9._/-]+$ && "$B" != -* && "${M:-completa}" =~ ^(completa|tipos|sencillo)$ ]] || exit 1
    rm -rf r; k=""; rama=$B; modo=${M:-completa}
    git clone -q --depth 1 --filter=blob:none --no-checkout --branch "$B" "$U" r || exit 1
  elif grep -qx "$k" <<< "$hechas"; then
    rm -rf r; k=""
    for linea in $(git ls-remote "$U" 'refs/heads/fabrica/*' | awk '{print $1 "@" $2}'); do
      kk=pc-$(huella "${linea%@*}")
      grep -qx "$kk" <<< "$hechas" && continue
      k=$kk; rama=${linea#*@refs/heads/}; modo=rama; break
    done
    [ -z "$k" ] && { rm -f llave; exit 0; }
    git clone -q --depth 1 --filter=blob:none --no-checkout --branch "$rama" "$U" r || exit 1
  fi
  git -C r sparse-checkout set pc && git -C r checkout -q || exit 1
  rm -f llave
  (cd r && git ls-files -z pc | tar -czf "$w/src.tgz" --null -T -) || exit 1
  mkdir -p ci && cp r/pc/ci/correr.sh ci/ && echo "$rama" > ci/rama.txt && env -i PATH="$PATH" python3 "$w/plan.py" "$modo" > ci/plan.txt || exit 1
  rm -rf r
  tar -cf p.tar src.tgz ci && rm -f src.tgz && node "$GITHUB_WORKSPACE/cifra.cjs" c p.tar p.enc || exit 1
  echo "k=$k" >> "$GITHUB_OUTPUT"
fi
rm -f p.tar
# Una fila por máquina: su número, el sistema, Windows (w) o Linux (l), y sus minutos de tope. La máquina virtual de Windows
# (tanda vm) instala Windows entero: 330 min, por debajo del tope de 6 h de GitHub.
python3 -c '
import json, sys
filas = [{"i": i, "so": "windows-latest" if l.split()[3] == "w" else "ubuntu-24.04", "min": 330 if l.split()[0] == "vm" else 60} for i, l in enumerate(x for x in open(sys.argv[1]) if x.strip())]
print("m=" + json.dumps(filas))' ci/plan.txt >> "$GITHUB_OUTPUT"
