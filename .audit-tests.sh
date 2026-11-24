#!/usr/bin/env bash
# Suite temporal de verificación. Se elimina al terminar.
set -Eeuo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
TMP="$ROOT/.audit-tmp"
IMG="$ROOT/assets/.audit"
rm -rf -- "$TMP" "$IMG"
mkdir -p "$TMP/webp" "$TMP/out" "$TMP/bin" "$IMG"
PASS=0
FAIL=0
CASE_STATUS=0
CASE_PATH=""

pass() { printf 'ok   %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'FALLO %s\n' "$1"; FAIL=$((FAIL + 1)); }
assert() { local d=$1; shift; if "$@" >/dev/null 2>&1; then pass "$d"; else fail "$d"; fi; }
refute() { local d=$1; shift; if "$@" >/dev/null 2>&1; then fail "$d"; else pass "$d"; fi; }
has() { grep -qF -- "$2" "$1"; }
has_re() { grep -qE -- "$2" "$1"; }
has_alpha() { [[ "$(identify -format '%[channels]' "$1")" == *a* ]]; }

for tool in sed grep cp mkdir mv rm date file dirname basename uname head cat; do
  ln -sf "$(command -v "$tool")" "$TMP/bin/$tool"
done

convert -size 40x60 xc:none -fill '#00FFA3' -draw 'circle 20,30 20,5' "$IMG/transparente.png"
convert "$IMG/transparente.png" "$IMG/foto.jpg"
cp -- "$ROOT/.webp-cache/poster.webp" "$IMG/ya.webp"
cp -- "$IMG/transparente.png" "$IMG/con espacio.png"
cp -- "$IMG/transparente.png" "$IMG/afiche_único.png"
head -c 120 "$ROOT/assets/favicon.png" > "$IMG/corrupto.png"

original_sum=$(sha256sum "$IMG/transparente.png" | cut -d' ' -f1)

case_gen() {
  local name=$1 poster=$2 slides=${3:-0}
  local out=".audit-tmp/out/$name" expr
  local script="$ROOT/.audit-$name.sh"
  mkdir -p -- "$ROOT/$out"
  cp -- "$ROOT/generate.sh" "$script"
  sed -i "s|^POSTER=.*|POSTER=\"$poster\"|" "$script"
  sed -i "s|^OUTPUT_DIR=.*|OUTPUT_DIR=\"$out\"|" "$script"
  sed -i '/^SLIDER_IMAGES=(/,/^)/c\SLIDER_IMAGES=()' "$script"
  if [[ "$slides" == 1 ]]; then
    sed -i '/^SLIDER_IMAGES=()/a SLIDER_IMAGES+=("assets/.audit/transparente.png")\nSLIDER_IMAGES+=("assets/.audit/foto.jpg")' "$script"
  fi
  if (($# >= 3)); then shift 3; else shift 2; fi
  for expr in "$@"; do sed -i "$expr" "$script"; done
  CASE_STATUS=0
  if [[ -n "$CASE_PATH" ]]; then
    env PATH="$CASE_PATH" /bin/bash "$script" > "$TMP/$name.log" 2>&1 || CASE_STATUS=$?
  else
    /bin/bash "$script" > "$TMP/$name.log" 2>&1 || CASE_STATUS=$?
  fi
}

P='assets/.audit/transparente.png'

# --- WebP ---
case_gen png "$P"
assert 'PNG convertido a WebP' test -s "$TMP/out/png/assets/.audit/transparente.webp"
assert 'transparencia preservada' has_alpha "$TMP/out/png/assets/.audit/transparente.webp"
assert 'PNG original intacto' test "$(sha256sum "$IMG/transparente.png" | cut -d' ' -f1)" = "$original_sum"
assert 'HTML usa WebP' has "$TMP/out/png/index.html" 'srcset="assets/.audit/transparente.webp"'
assert 'HTML conserva fallback' has "$TMP/out/png/index.html" "src=\"$P\""

case_gen jpg 'assets/.audit/foto.jpg'
assert 'JPEG convertido' test -s "$TMP/out/jpg/assets/.audit/foto.webp"
assert 'dimensiones preservadas' test "$(identify -format '%wx%h' "$TMP/out/jpg/assets/.audit/foto.webp")" = 40x60

case_gen webp 'assets/.audit/ya.webp'
assert 'WebP existente referenciado' has "$TMP/out/webp/index.html" 'src="assets/.audit/ya.webp"'
refute 'sin <picture> redundante' has "$TMP/out/webp/index.html" '<picture>'

case_gen spaces 'assets/.audit/con espacio.png'
assert 'nombre con espacio convertido' test -s "$TMP/out/spaces/assets/.audit/con espacio.webp"
assert 'srcset con espacio' has "$TMP/out/spaces/index.html" 'srcset="assets/.audit/con espacio.webp"'

case_gen unicode 'assets/.audit/afiche_único.png'
assert 'nombre Unicode convertido' test -s "$TMP/out/unicode/assets/.audit/afiche_único.webp"
assert 'srcset Unicode' has "$TMP/out/unicode/index.html" 'srcset="assets/.audit/afiche_único.webp"'

CASE_PATH="$TMP/bin" case_gen notool "$P"
assert 'sin herramienta avisa' has "$TMP/notool.log" 'Sin herramienta WebP'
assert 'sin herramienta muestra instrucción' has_re "$TMP/notool.log" 'Necesitas cwebp:'
assert 'sin herramienta sirve original' test -s "$TMP/out/notool/$P"
refute 'sin herramienta no genera WebP' test -e "$TMP/out/notool/assets/.audit/transparente.webp"

case_gen broken 'assets/.audit/corrupto.png'
assert 'error de conversión avisa' has_re "$TMP/broken.log" 'No se pudo convertir|Formato no convertible'
assert 'error de conversión conserva original' test -s "$TMP/out/broken/assets/.audit/corrupto.png"
refute 'error de conversión sin WebP' test -e "$TMP/out/broken/assets/.audit/corrupto.webp"

case_gen off "$P" 0 's|^CONVERT_WEBP=.*|CONVERT_WEBP=false|'
refute 'CONVERT_WEBP=false' test -e "$TMP/out/off/assets/.audit/transparente.webp"
assert 'CONVERT_WEBP=false genera sitio' test -s "$TMP/out/off/index.html"

case_gen badq "$P" 0 's|^WEBP_QUALITY=.*|WEBP_QUALITY=101|'
assert 'WEBP_QUALITY inválido falla' test "$CASE_STATUS" -ne 0
assert 'WEBP_QUALITY inválido avisa' has "$TMP/badq.log" 'WEBP_QUALITY'

case_gen badend "$P" 0 \
  's|^EVENT_DATE=.*|EVENT_DATE="2026-12-08"|' \
  's|^EVENT_END_DATE=.*|EVENT_END_DATE="2026-12-07"|'
assert 'fin anterior al inicio falla' test "$CASE_STATUS" -ne 0
assert 'fin anterior avisa' has "$TMP/badend.log" 'posterior al inicio'

case_gen badtz "$P" 0 's|^EVENT_TIMEZONE=.*|EVENT_TIMEZONE="Marte/Base"|'
assert 'zona horaria inválida falla' test "$CASE_STATUS" -ne 0

# --- Switches ---
case_gen both "$P" 1
assert 'ambos: enlace detalles' has "$TMP/out/both/index.html" 'href="#detalles"'
assert 'ambos: enlace charlas' has "$TMP/out/both/index.html" 'href="#charlas"'
assert 'ambos: lista de detalles' has "$TMP/out/both/index.html" 'id="detalles"'
assert 'ambos: sección de charlas' has "$TMP/out/both/index.html" 'id="charlas"'
assert 'ambos: título configurable' has "$TMP/out/both/index.html" 'Charlas y participantes'

case_gen none "$P" 1 \
  's|^SHOW_EVENT_DETAILS=.*|SHOW_EVENT_DETAILS=false|' \
  's|^SHOW_TALKS=.*|SHOW_TALKS=false|'
refute 'ninguno: sin navegación vacía' has "$TMP/out/none/index.html" '<nav'
refute 'ninguno: sin detalles' has "$TMP/out/none/index.html" 'id="detalles"'
refute 'ninguno: sin charlas' has "$TMP/out/none/index.html" 'id="charlas"'
assert 'ninguno: sitio válido' has "$TMP/out/none/index.html" '<main'

case_gen onlydetails "$P" 1 's|^SHOW_TALKS=.*|SHOW_TALKS=false|'
assert 'solo detalles: enlace' has "$TMP/out/onlydetails/index.html" 'href="#detalles"'
refute 'solo detalles: sin charlas' has "$TMP/out/onlydetails/index.html" 'id="charlas"'

case_gen onlytalks "$P" 1 \
  's|^SHOW_EVENT_DETAILS=.*|SHOW_EVENT_DETAILS=false|' \
  's|^SECTION_TALKS_TITLE=.*|SECTION_TALKS_TITLE="Programa de ponencias"|'
assert 'solo charlas: enlace con nombre configurable' has "$TMP/out/onlytalks/index.html" 'Programa de ponencias'
refute 'solo charlas: sin detalles' has "$TMP/out/onlytalks/index.html" 'id="detalles"'
assert 'solo charlas: etiqueta accesible' has "$TMP/out/onlytalks/index.html" 'aria-label="Programa de ponencias"'

# --- Countdown: configuraciones para inspección en navegador ---
future=$(TZ=America/La_Paz date -d '+1 day' +%F)
past=$(TZ=America/La_Paz date -d '-2 days' +%F)
yesterday=$(TZ=America/La_Paz date -d '-1 day' +%F)
nowhm=$(TZ=America/La_Paz date +%H:%M)
today=$(TZ=America/La_Paz date +%F)

case_gen cd_future "$P" 0 "s|^EVENT_DATE=.*|EVENT_DATE=\"$future\"|"
case_gen cd_starting "$P" 0 \
  "s|^EVENT_DATE=.*|EVENT_DATE=\"$today\"|" \
  "s|^EVENT_TIME=.*|EVENT_TIME=\"$nowhm\"|" \
  's|^EVENT_STARTING_DURATION=.*|EVENT_STARTING_DURATION=86400|'
case_gen cd_running "$P" 0 "s|^EVENT_DATE=.*|EVENT_DATE=\"$past\"|"
case_gen cd_finished "$P" 0 \
  "s|^EVENT_DATE=.*|EVENT_DATE=\"$past\"|" \
  "s|^EVENT_END_DATE=.*|EVENT_END_DATE=\"$yesterday\"|"
case_gen cd_endtime "$P" 0 \
  "s|^EVENT_DATE=.*|EVENT_DATE=\"$past\"|" \
  "s|^EVENT_END_DATE=.*|EVENT_END_DATE=\"$yesterday\"|" \
  's|^EVENT_END_TIME=.*|EVENT_END_TIME="23:59"|'
assert 'HTML expone hora final' has "$TMP/out/cd_endtime/index.html" "data-end-date=\"$yesterday\""
assert 'HTML expone duración de inicio' has "$TMP/out/cd_starting/index.html" 'data-starting-duration="86400"'

printf '\nResultado: %d correctas, %d fallidas\n' "$PASS" "$FAIL"
((FAIL == 0)) || exit 1
