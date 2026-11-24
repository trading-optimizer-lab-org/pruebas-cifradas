#!/usr/bin/env bash
# Prepara el paquete cifrado de una pasada y dice cuántas máquinas hacen falta. No escribe nada legible:
# el código solo existe descifrado dentro de la máquina, y lo que sale es un número de máquinas y una huella.
#  - Lanzada a mano (A): el paquete ya viene cifrado desde el PC.
#  - Cada 10 minutos: trae la rama main del repositorio privado y pasa las pruebas si la carpeta de la app cambió desde la última pasada.
#  - De noche: pasada completa más pruebas al azar, y limpieza de pasadas viejas.
set -u
w=$RUNNER_TEMP/f; mkdir -p "$w"; cd "$w" || exit 1
R=$GITHUB_REPOSITORY
echo "t=[]" >> "$GITHUB_OUTPUT"; echo "e1=[]" >> "$GITHUB_OUTPUT"; echo "e2=[]" >> "$GITHUB_OUTPUT"

if [ -n "${A:-}" ]; then
  curl -sSfL -H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/octet-stream" "https://api.github.com/repos/$R/releases/assets/$A" -o p.enc || exit 1
  node "$GITHUB_WORKSPACE/cifra.cjs" d p.enc p.tar && tar -xf p.tar ci/plan.txt || exit 1
else
  modo=completa
  [ "${SCHED:-}" = "17 1 * * *" ] && modo=noche
  [ "${EV:-}" = workflow_dispatch ] && [ -n "${M:-}" ] && modo=$M
  if [ "$modo" = noche ]; then
    # Pasadas de más de 3 días, fuera. Y una señal de vida al mes, porque GitHub apaga lo programado en repositorios quietos 60 días.
    viejo=$(date -u -d '3 days ago' +%FT%TZ)
    gh run list -R "$R" -L 1000 --json databaseId,createdAt -q ".[] | select(.createdAt < \"$viejo\") | .databaseId" |
      while read -r id; do gh api -X DELETE "repos/$R/actions/runs/$id" || true; done
    ultimo=$(gh api "repos/$R/commits/main" -q .commit.committer.date)
    if [ "$(date -u -d "$ultimo" +%s)" -lt "$(date -u -d '30 days ago' +%s)" ]; then
      sha=$(gh api "repos/$R/git/ref/heads/main" -q .object.sha); arbol=$(gh api "repos/$R/git/commits/$sha" -q .tree.sha)
      nuevo=$(gh api "repos/$R/git/commits" -f message=vivo -f tree="$arbol" -f "parents[]=$sha" -q .sha)
      gh api -X PATCH "repos/$R/git/refs/heads/main" -f sha="$nuevo" || true
    fi
  fi
  install -m 600 /dev/null llave && printf '%s\n' "$LLAVE" > llave
  export GIT_SSH_COMMAND="ssh -i $w/llave -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
  # La dirección del repositorio privado y el nombre de la carpeta vienen de secretos, no de este archivo.
  C=$CARPETA
  git clone -q --depth 1 --filter=blob:none --no-checkout "$RUTA_PRIVADA" r || exit 1
  # Huella de la carpeta de la app mezclada con la clave: dice si ya se probó sin decir qué hay dentro.
  k=$(printf '%s%s' "$CLAVE" "$(git -C r rev-parse "HEAD:$C")" | sha256sum | cut -c1-20)
  if [ "$modo" = completa ] && gh cache list -R "$R" --key "hecho-$k" --json key -q '.[].key' | grep -q .; then rm -f llave; exit 0; fi
  git -C r sparse-checkout set "$C" && git -C r checkout -q || exit 1
  rm -f llave
  (cd r && git ls-files -z "$C" | tar -cf "$w/src.tar" --null -T -) || exit 1
  mkdir -p ci && cp "r/$C/tools/ci/correr.sh" ci/ && echo "$C" > ci/sub.txt && python3 "r/$C/tools/ci/plan.py" "$modo" > ci/plan.txt || exit 1
  # Para el veredicto del trabajo j; mientras main no los tenga, j deja un veredicto NO que lo dice.
  cp "r/$C/tools/ci/veredicto.cjs" "r/$C/tools/ci/fallos-conocidos.txt" ci/ 2>/dev/null || true
  rm -rf r
  tar -cf p.tar src.tar ci && rm -f src.tar && node "$GITHUB_WORKSPACE/cifra.cjs" c p.tar p.enc || exit 1
  [ "$modo" = completa ] && echo "k=$k" >> "$GITHUB_OUTPUT"
fi
rm -f p.tar
python3 "$GITHUB_WORKSPACE/reparto.py" ci/plan.txt >> "$GITHUB_OUTPUT"
