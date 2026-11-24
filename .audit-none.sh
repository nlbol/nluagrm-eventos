#!/usr/bin/env bash
# Genera una landing page estática para un evento.
# Edita la CONFIGURACIÓN de abajo y ejecuta: ./generate.sh
set -Eeuo pipefail

# ============================================================
# CONFIGURACIÓN DEL EVENTO
# ============================================================

EVENT_NAME="HackPoint"
EVENT_DESCRIPTION="Una jornada de la comunidad GNU/Linux y Seguridad Informatica: charlas y demos."
EVENT_DATE="2026-12-06"
EVENT_TIME="09:00"
EVENT_TIMEZONE="America/La_Paz"

# presencial | online
EVENT_MODE="online"
EVENT_LOCATION="Santa Cruz de la Sierra, Bolivia"
EVENT_MAP_URL="https://www.openstreetmap.org/search?query=Santa%20Cruz%20de%20la%20Sierra"
EVENT_URL="https://meet.google.com"

REGISTER_ENABLED=true
REGISTER_URL="https://cloud.nluagrm.org/"
REGISTER_LABEL="Registrarme"

POSTER="assets/.audit/transparente.png"
POSTER_ALT="Afiche de HackPoint 2026"

SLIDER_IMAGES=()
SLIDER_IMAGES+=("assets/.audit/transparente.png")
SLIDER_IMAGES+=("assets/.audit/foto.jpg")
SLIDER_INTERVAL=5000

# Secciones independientes.
SHOW_EVENT_DETAILS=false
SHOW_TALKS=false
SECTION_TALKS_TITLE="Charlas y participantes"

# Inicio: EVENT_DATE + EVENT_TIME en EVENT_TIMEZONE.
# EVENT_END_DATE vacío = sin fin; el evento se considera en curso.
EVENT_END_DATE=""
EVENT_END_TIME=""              # vacío => 23:59 de EVENT_END_DATE
EVENT_STARTING_DURATION=300    # segundos del estado "INICIANDO"

# Optimización WebP (los originales nunca se modifican).
CONVERT_WEBP=true
WEBP_QUALITY=82                # 1-100; se ignora si WEBP_LOSSLESS=true
WEBP_LOSSLESS=false
WEBP_INSTALL_TOOLS=false       # true permite proponer instalación con confirmación

OUTPUT_DIR=".audit-tmp/out/none"
CNAME_NAME="eventos.nluagrm.org"

# Colores manuales opcionales. Vacío = identidad fija del afiche HackPoint.
# Ejemplo: COLOR_ACCENT="#00FFA3"
COLOR_ACCENT=""
COLOR_SECONDARY=""
COLOR_BACKGROUND=""

# ============================================================
# FIN DE LA CONFIGURACIÓN
# ============================================================

VERSION="2.1.0"
DRY_RUN=0
CHECK_ONLY=0
NO_SLIDER=0
PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
BUILD_DIR=""
OUTPUT_ABS=""
ASSET_COUNT=0
WEBP_CACHE="$PROJECT_DIR/.webp-cache"
WEBP_BIN=""
WEBP_KIND=""
WEBP_COUNT=0
WEBP_POSTER=0
WEBP_SLIDER=()
WEBP_FAVICON=0

log() { printf '[generate] %s\n' "$*"; }
warn() { printf '[generate] advertencia: %s\n' "$*" >&2; }
die() { printf '[generate] error: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Generador de landing pages estáticas para eventos.

Uso:
  ./generate.sh [opciones]

Opciones:
  -h, --help              Muestra esta ayuda.
      --dry-run           Valida y construye sin publicar en OUTPUT_DIR.
      --check             Solo valida la configuración y los assets.
  -o, --output DIR        Directorio de salida (por defecto: public).
  -e, --event NOMBRE      Sobrescribe EVENT_NAME.
      --poster ARCHIVO    Sobrescribe POSTER.
      --mode MODO         presencial u online.
      --no-slider         Ignora SLIDER_IMAGES.
      --slider-interval MS  Intervalo del slider (1000-120000).
  -V, --version           Muestra la versión.

La configuración principal se edita al inicio de generate.sh.
EOF
}

# Escapa texto para usarlo dentro de HTML o atributos.
h() {
  local s=$1
  s=${s//&/&amp;}
  s=${s//</&lt;}
  s=${s//>/&gt;}
  s=${s//\"/&quot;}
  s=${s//\'/&#39;}
  printf '%s' "$s"
}

valid_url() {
  [[ $1 =~ ^https://[^[:space:]]+$ ]] || [[ $1 =~ ^http://[^[:space:]]+$ ]]
}

valid_date() {
  [[ $1 =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || return 1
  local year=${1:0:4} month=${1:5:2} day=${1:8:2}
  ((10#$month >= 1 && 10#$month <= 12)) || return 1
  ((10#$day >= 1 && 10#$day <= 31)) || return 1
  if command -v date >/dev/null 2>&1 && date -d "$1" +%F >/dev/null 2>&1; then
    [[ "$(date -d "$1" +%F)" == "$1" ]] || return 1
  fi
  return 0
}

valid_time() {
  [[ $1 =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]
}

valid_bool() {
  case "$1" in true|false) return 0 ;; *) return 1 ;; esac
}

valid_uint() {
  [[ $1 =~ ^[0-9]+$ ]] && ((10#$1 >= $2 && 10#$1 <= $3))
}

parse_args() {
  while (($#)); do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      -V|--version) printf 'generate.sh %s\n' "$VERSION"; exit 0 ;;
      --dry-run) DRY_RUN=1; shift ;;
      --check) CHECK_ONLY=1; shift ;;
      --no-slider) NO_SLIDER=1; shift ;;
      -o|--output)
        (($# >= 2)) || die "$1 requiere un valor"
        OUTPUT_DIR=$2; shift 2 ;;
      --output=*) OUTPUT_DIR=${1#*=}; shift ;;
      -e|--event)
        (($# >= 2)) || die "$1 requiere un valor"
        EVENT_NAME=$2; shift 2 ;;
      --event=*) EVENT_NAME=${1#*=}; shift ;;
      --poster)
        (($# >= 2)) || die "$1 requiere un valor"
        POSTER=$2; shift 2 ;;
      --poster=*) POSTER=${1#*=}; shift ;;
      --mode)
        (($# >= 2)) || die "$1 requiere un valor"
        EVENT_MODE=$2; shift 2 ;;
      --mode=*) EVENT_MODE=${1#*=}; shift ;;
      --slider-interval)
        (($# >= 2)) || die "$1 requiere un valor"
        SLIDER_INTERVAL=$2; shift 2 ;;
      --slider-interval=*) SLIDER_INTERVAL=${1#*=}; shift ;;
      *) die "opción desconocida: $1 (usa --help)" ;;
    esac
  done
}

# Ruta absoluta dentro del proyecto. Rechaza rutas vacías y symlinks.
resolve_asset() {
  local relative=$1 absolute
  [[ -n "$relative" ]] || die "ruta de asset vacía"
  [[ "$relative" != /* ]] || die "las rutas de assets deben ser relativas: $relative"
  [[ "$relative" != *".."* ]] || die "ruta de asset no permitida: $relative"
  [[ "$relative" != *\\* ]] || die "ruta de asset no permitida: $relative"
  absolute="$PROJECT_DIR/$relative"
  [[ -f "$absolute" ]] || die "no existe el asset: $relative"
  [[ ! -L "$absolute" ]] || die "los symlinks no están permitidos: $relative"
  case "${absolute,,}" in
    *.png|*.jpg|*.jpeg|*.webp|*.svg|*.avif|*.gif) ;;
    *) die "formato de imagen no soportado: $relative" ;;
  esac
  RESOLVED_ASSET=$absolute
}

# --- Optimización WebP ----------------------------------------------------
# Los originales nunca se sobrescriben. Las copias WebP se guardan en
# .webp-cache/ y se reutilizan si son más recientes que el original.

detect_webp_tool() {
  local encoders=""
  WEBP_BIN=""
  WEBP_KIND=""
  if command -v cwebp >/dev/null 2>&1; then
    WEBP_BIN=cwebp; WEBP_KIND=cwebp; return 0
  fi
  if command -v magick >/dev/null 2>&1; then
    WEBP_BIN=magick; WEBP_KIND=magick; return 0
  fi
  if command -v convert >/dev/null 2>&1; then
    WEBP_BIN=convert; WEBP_KIND=magick; return 0
  fi
  if command -v ffmpeg >/dev/null 2>&1; then
    encoders=$(ffmpeg -hide_banner -encoders 2>/dev/null || true)
    if [[ "$encoders" == *libwebp* ]]; then
      WEBP_BIN=ffmpeg; WEBP_KIND=ffmpeg; return 0
    fi
  fi
  return 1
}

PKG_BIN=""
PKG_NAME=""
PKG_HINT=""
OS_NAME=""

detect_package_manager() {
  OS_NAME="$(uname -s 2>/dev/null || printf 'sistema desconocido')"
  if [[ -r /etc/os-release ]]; then
    local pretty
    pretty=$(sed -n 's/^PRETTY_NAME="\?\([^"]*\)"\?.*/\1/p' /etc/os-release | head -n 1)
    [[ -z "$pretty" ]] || OS_NAME=$pretty
  fi
  for PKG_BIN in apt dnf yum pacman zypper apk; do
    command -v "$PKG_BIN" >/dev/null 2>&1 || continue
    case "$PKG_BIN" in
      apt) PKG_NAME=webp ;;
      dnf|yum|zypper) PKG_NAME=libwebp-tools ;;
      pacman) PKG_NAME=libwebp ;;
      apk) PKG_NAME=libwebp-tools ;;
    esac
    PKG_HINT="$PKG_BIN install $PKG_NAME"
    [[ "$PKG_BIN" != pacman ]] || PKG_HINT="pacman -S $PKG_NAME"
    [[ "$PKG_BIN" != apk ]] || PKG_HINT="apk add $PKG_NAME"
    return 0
  done
  PKG_BIN=""
  PKG_NAME=""
  PKG_HINT="instala cwebp (libwebp) desde tu gestor de paquetes"
  return 1
}

ensure_webp_tool() {
  detect_webp_tool && return 0
  [[ "$CONVERT_WEBP" == true ]] || return 1

  detect_package_manager || true
  warn "Sin herramienta WebP en $OS_NAME. Necesitas cwebp: $PKG_HINT"
  if [[ "$WEBP_INSTALL_TOOLS" != true ]]; then
    log "Se servirán los originales; la conversión se omite."
    return 1
  fi
  if [[ ! -t 0 ]]; then
    warn "Sin terminal interactiva: no se instalará nada. Instala manualmente: $PKG_HINT"
    return 1
  fi

  local answer=""
  printf '[generate] ¿Instalar %s ahora? [s/N] ' "$PKG_NAME" >&2
  IFS= read -r answer || answer=""
  case "${answer,,}" in
    s|si|sí|y|yes) ;;
    *) log "Instalación cancelada."; return 1 ;;
  esac
  if (( EUID != 0 )); then
    warn "Se requieren permisos de administrador: ejecuta '$PKG_HINT' con sudo y vuelve a generar."
    return 1
  fi
  [[ -n "$PKG_BIN" ]] || return 1
  case "$PKG_BIN" in
    apt|dnf|yum|zypper) "$PKG_BIN" install -y "$PKG_NAME" ;;
    pacman) "$PKG_BIN" -S --noconfirm "$PKG_NAME" ;;
    apk) "$PKG_BIN" add "$PKG_NAME" ;;
    *) warn "Gestor de paquetes no soportado para instalación automática."; return 1 ;;
  esac
  detect_webp_tool || { warn "La herramienta sigue sin estar disponible."; return 1; }
  return 0
}

is_image_file() {
  local path=$1 mime=""
  case "${path,,}" in
    *.png|*.jpg|*.jpeg|*.bmp|*.tif|*.tiff|*.gif|*.avif|*.webp|*.svg) ;;
    *) return 1 ;;
  esac
  if command -v file >/dev/null 2>&1; then
    mime=$(file -b --mime-type -- "$path" 2>/dev/null || true)
    [[ -z "$mime" || "$mime" == image/* ]] || return 1
  fi
  return 0
}

webp_rel_for() {
  local rel
  if [[ "$1" == "$PROJECT_DIR"/assets/* ]]; then rel=${1#"$PROJECT_DIR"/assets/}
  else rel=${1#assets/}; fi
  printf 'assets/%s.webp' "${rel%.*}"
}

webp_cache_for() {
  local rel key
  if [[ "$1" == "$PROJECT_DIR"/assets/* ]]; then rel=${1#"$PROJECT_DIR"/assets/}
  else rel=${1#assets/}; fi
  key=${rel%.*}; key=${key//\//__}
  printf '%s/%s.webp' "$WEBP_CACHE" "$key"
}

# Convierte un archivo a WebP. Éxito: 0. Fallo o no aplicable: 1.
convert_to_webp() {
  local source=$1 target=$2 tmp dir ok=0 rel=${3:-${1##*/}}
  [[ -f "$source" && -s "$source" ]] || return 1
  case "${source,,}" in
    *.svg) log "SVG servido sin conversión: $rel"; return 1 ;;
  esac
  is_image_file "$source" || { warn "Formato no convertible a WebP: $rel"; return 1; }
  [[ -s "$target" && "$target" -nt "$source" ]] && return 0

  dir=$(dirname -- "$target")
  mkdir -p -- "$dir" || return 1
  # Un WebP ya optimizado solo se copia a la caché: no se recomprime.
  if [[ "${source,,}" == *.webp ]]; then
    if cp -- "$source" "$target"; then return 0; fi
    warn "No se pudo copiar el WebP existente: $rel"
    return 1
  fi
  tmp="$dir/.tmp.$$.${RANDOM}.webp"

  case "$WEBP_KIND" in
    cwebp)
      if [[ "$WEBP_LOSSLESS" == true ]]; then
        if cwebp -quiet -lossless -o "$tmp" "$source" >/dev/null 2>&1; then ok=1; fi
      else
        if cwebp -quiet -q "$WEBP_QUALITY" -o "$tmp" "$source" >/dev/null 2>&1; then ok=1; fi
      fi
      ;;
    magick)
      if [[ "$WEBP_LOSSLESS" == true ]]; then
        if "$WEBP_BIN" "$source" -auto-orient -define webp:lossless=true \
             -define webp:alpha-quality=100 "$tmp" >/dev/null 2>&1; then ok=1; fi
      else
        if "$WEBP_BIN" "$source" -auto-orient -quality "$WEBP_QUALITY" \
             -define webp:alpha-quality=100 "$tmp" >/dev/null 2>&1; then ok=1; fi
      fi
      ;;
    ffmpeg)
      if [[ "$WEBP_LOSSLESS" == true ]]; then
        if ffmpeg -nostdin -hide_banner -loglevel error -y -i "$source" \
             -c:v libwebp -lossless 1 -pix_fmt yuva420p "$tmp" >/dev/null 2>&1; then ok=1; fi
      else
        if ffmpeg -nostdin -hide_banner -loglevel error -y -i "$source" \
             -c:v libwebp -q:v "$WEBP_QUALITY" -pix_fmt yuva420p "$tmp" >/dev/null 2>&1; then ok=1; fi
      fi
      ;;
  esac

  if ((ok)) && [[ -s "$tmp" ]]; then
    if mv -f -- "$tmp" "$target"; then return 0; fi
  fi
  rm -f -- "$tmp"
  warn "No se pudo convertir a WebP: $rel"
  return 1
}

prepare_webp() {
  WEBP_COUNT=0; WEBP_POSTER=0; WEBP_SLIDER=(); WEBP_FAVICON=0
  [[ "$CONVERT_WEBP" == true ]] || { log "Conversión WebP desactivada."; return 0; }
  ensure_webp_tool || return 0

  local i=0 image target
  target=$(webp_cache_for "$POSTER_PATH")
  if convert_to_webp "$POSTER_PATH" "$target" "$POSTER"; then
    WEBP_POSTER=1; WEBP_COUNT=$((WEBP_COUNT + 1))
  fi
  for image in "${SLIDER_PATHS[@]}"; do
    target=$(webp_cache_for "$image")
    if convert_to_webp "$image" "$target" "${image##*/}"; then
      WEBP_SLIDER[$i]=1; WEBP_COUNT=$((WEBP_COUNT + 1))
    else
      WEBP_SLIDER[$i]=0
    fi
    i=$((i + 1))
  done
  if [[ -f "$PROJECT_DIR/assets/favicon.png" ]]; then
    target=$(webp_cache_for "$PROJECT_DIR/assets/favicon.png")
    if convert_to_webp "$PROJECT_DIR/assets/favicon.png" "$target" "favicon.png"; then
      WEBP_FAVICON=1; WEBP_COUNT=$((WEBP_COUNT + 1))
    fi
  fi
  ASSET_COUNT=$((ASSET_COUNT + WEBP_COUNT))
  log "WebP: $WEBP_COUNT imagen(es) optimizada(s) con $WEBP_KIND ($WEBP_BIN)"
}

validate() {
  [[ -n "$EVENT_NAME" ]] || die "EVENT_NAME está vacío"
  [[ -n "$EVENT_DESCRIPTION" ]] || die "EVENT_DESCRIPTION está vacío"
  valid_date "$EVENT_DATE" || die "EVENT_DATE debe ser una fecha válida AAAA-MM-DD: $EVENT_DATE"
  valid_time "$EVENT_TIME" || die "EVENT_TIME debe tener formato HH:MM: $EVENT_TIME"
  local zone_root zone_ok=0
  for zone_root in /usr/share/zoneinfo /usr/lib/zoneinfo /etc/zoneinfo; do
    if [[ -f "$zone_root/$EVENT_TIMEZONE" ]]; then zone_ok=1; break; fi
  done
  if ((zone_ok == 0)) && command -v timedatectl >/dev/null 2>&1; then
    if timedatectl list-timezones 2>/dev/null | grep -qxF "$EVENT_TIMEZONE"; then zone_ok=1; fi
  fi
  ((zone_ok == 1)) || die "EVENT_TIMEZONE no es válida o no está disponible: $EVENT_TIMEZONE"
  TZ="$EVENT_TIMEZONE" date +%z >/dev/null 2>&1 ||
    die "EVENT_TIMEZONE no es usable: $EVENT_TIMEZONE"
  [[ "$EVENT_MODE" == presencial || "$EVENT_MODE" == online ]] ||
    die "EVENT_MODE debe ser 'presencial' u 'online': $EVENT_MODE"
  valid_uint "$SLIDER_INTERVAL" 1000 120000 ||
    die "SLIDER_INTERVAL debe ser un entero entre 1000 y 120000"
  valid_uint "$EVENT_STARTING_DURATION" 0 86400 ||
    die "EVENT_STARTING_DURATION debe ser un entero entre 0 y 86400"

  if [[ -n "$EVENT_END_DATE" ]]; then
    valid_date "$EVENT_END_DATE" || die "EVENT_END_DATE debe ser AAAA-MM-DD: $EVENT_END_DATE"
    [[ -n "$EVENT_END_TIME" ]] || EVENT_END_TIME="23:59"
    valid_time "$EVENT_END_TIME" || die "EVENT_END_TIME debe tener formato HH:MM: $EVENT_END_TIME"
    [[ "${EVENT_END_DATE}T${EVENT_END_TIME}" > "${EVENT_DATE}T${EVENT_TIME}" ]] ||
      die "EVENT_END debe ser posterior al inicio del evento"
  fi

  valid_bool "$SHOW_EVENT_DETAILS" || die "SHOW_EVENT_DETAILS debe ser true o false"
  valid_bool "$SHOW_TALKS" || die "SHOW_TALKS debe ser true o false"
  [[ -n "$SECTION_TALKS_TITLE" ]] || die "SECTION_TALKS_TITLE está vacío"
  valid_bool "$CONVERT_WEBP" || die "CONVERT_WEBP debe ser true o false"
  valid_bool "$WEBP_LOSSLESS" || die "WEBP_LOSSLESS debe ser true o false"
  valid_bool "$WEBP_INSTALL_TOOLS" || die "WEBP_INSTALL_TOOLS debe ser true o false"
  valid_uint "$WEBP_QUALITY" 1 100 || die "WEBP_QUALITY debe ser un entero entre 1 y 100"

  if [[ "$EVENT_MODE" == online ]]; then
    [[ -n "$EVENT_URL" ]] || warn "EVENT_MODE=online sin EVENT_URL: se muestra la modalidad sin enlace"
    [[ -z "$EVENT_URL" ]] || valid_url "$EVENT_URL" ||
      die "EVENT_URL no es una URL válida: $EVENT_URL"
  else
    [[ -n "$EVENT_LOCATION" ]] || die "EVENT_LOCATION es obligatorio en modo presencial"
    [[ -z "$EVENT_MAP_URL" ]] || valid_url "$EVENT_MAP_URL" ||
      die "EVENT_MAP_URL no es una URL válida: $EVENT_MAP_URL"
  fi

  case "$REGISTER_ENABLED" in
    true|false) ;;
    *) die "REGISTER_ENABLED debe ser true o false: $REGISTER_ENABLED" ;;
  esac
  if [[ "$REGISTER_ENABLED" == true ]]; then
    valid_url "$REGISTER_URL" || die "REGISTER_URL no es válida: $REGISTER_URL"
    [[ -n "$REGISTER_LABEL" ]] || die "REGISTER_LABEL está vacío"
  fi

  for value in "$COLOR_ACCENT" "$COLOR_SECONDARY" "$COLOR_BACKGROUND"; do
    [[ -z "$value" || "$value" =~ ^#[0-9a-fA-F]{6}$ ]] ||
      die "los colores manuales deben ser hexadecimales de 6 dígitos: $value"
  done
  if [[ -n "$CNAME_NAME" ]]; then
    [[ "$CNAME_NAME" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] ||
      die "CNAME_NAME no es un nombre de host válido: $CNAME_NAME"
  fi

  RESOLVED_ASSET=""
  resolve_asset "$POSTER"
  POSTER_PATH=$RESOLVED_ASSET
  SLIDER_PATHS=()
  if ((NO_SLIDER == 0)); then
    local image
    for image in "${SLIDER_IMAGES[@]}"; do
      RESOLVED_ASSET=""
      resolve_asset "$image"
      SLIDER_PATHS+=("$RESOLVED_ASSET")
    done
  fi
  ASSET_COUNT=$((1 + ${#SLIDER_PATHS[@]}))
  if [[ -f "$PROJECT_DIR/assets/favicon.png" ]]; then
    ASSET_COUNT=$((ASSET_COUNT + 1))
  fi

  local base parent parent_canon
  [[ -n "$OUTPUT_DIR" && "$OUTPUT_DIR" != / ]] || die "OUTPUT_DIR inválido: $OUTPUT_DIR"
  [[ "$OUTPUT_DIR" != "." && "$OUTPUT_DIR" != ".." ]] || die "OUTPUT_DIR inválido: $OUTPUT_DIR"
  if [[ "$OUTPUT_DIR" == /* ]]; then base=$OUTPUT_DIR; else base="$PROJECT_DIR/$OUTPUT_DIR"; fi
  [[ "$(basename -- "$base")" != ".." ]] || die "OUTPUT_DIR inválido: $OUTPUT_DIR"
  parent=$(dirname -- "$base")
  [[ -d "$parent" ]] || die "no existe el directorio padre de OUTPUT_DIR: $parent"
  parent_canon="$(cd -- "$parent" && pwd -P)"
  OUTPUT_ABS="$parent_canon/$(basename -- "$base")"
  [[ "$OUTPUT_ABS" != "$PROJECT_DIR" ]] || die "OUTPUT_DIR no puede ser la raíz del proyecto"
  [[ "$OUTPUT_ABS" == "$PROJECT_DIR"/* ]] || die "OUTPUT_DIR debe estar dentro del proyecto"
  [[ "$OUTPUT_ABS" != "$PROJECT_DIR/assets" && "$OUTPUT_ABS" != "$PROJECT_DIR/assets/"* ]] ||
    die "OUTPUT_DIR no puede ser ni estar dentro de assets/"
  [[ "$OUTPUT_ABS" != "$PROJECT_DIR/.git" && "$OUTPUT_ABS" != "$PROJECT_DIR/.git/"* ]] ||
    die "OUTPUT_DIR no puede ser ni estar dentro de .git/"
  [[ ! -L "$OUTPUT_ABS" ]] || die "OUTPUT_DIR es un symlink: $OUTPUT_ABS"
  [[ ! -e "$OUTPUT_ABS" || -d "$OUTPUT_ABS" ]] || die "OUTPUT_DIR existe y no es un directorio"
}

write_html() {
  local file=$1 title desc name location_line mode_label mode_class mode_icon
  local action_html register_html poster_src poster_rel caption slider_html='' slide slide_img
  local caption_html='' i=0 favicon='' poster_open='' poster_close=''
  local nav_html='' details_html='' talks_title render_talks=0
  local end_date='' end_time=''

  title=$(h "$EVENT_NAME")
  desc=$(h "$EVENT_DESCRIPTION")
  name=$(h "${EVENT_NAME%% *}")
  talks_title=$(h "$SECTION_TALKS_TITLE")
  poster_rel=${POSTER#assets/}
  poster_src="assets/$poster_rel"
  if ((WEBP_POSTER)) && [[ "${POSTER,,}" != *.webp ]]; then
    poster_open="<picture><source srcset=\"$(h "$(webp_rel_for "$POSTER")")\" type=\"image/webp\">"
    poster_close='</picture>'
  fi

  favicon=''
  if [[ -f "$PROJECT_DIR/assets/favicon.png" ]]; then
    favicon='<link rel="icon" type="image/png" href="assets/favicon.png">'
    if ((WEBP_FAVICON)); then
      favicon="<link rel=\"icon\" type=\"image/webp\" href=\"$(h "$(webp_rel_for "$PROJECT_DIR/assets/favicon.png")")\">$favicon"
    fi
  fi

  if [[ "$SHOW_EVENT_DETAILS" == true ]]; then
    nav_html='      <a href="#detalles">Detalles</a>
'
  fi
  if [[ "$SHOW_TALKS" == true && ${#SLIDER_PATHS[@]} -gt 0 ]]; then
    render_talks=1
    nav_html+="      <a href=\"#charlas\">$talks_title</a>
"
  fi

  if [[ "$EVENT_MODE" == online ]]; then
    mode_label="Evento online"
    mode_class="online"
    mode_icon='<path d="M2 8.5a5.5 5.5 0 0 1 5.5-5.5h9A5.5 5.5 0 0 1 22 8.5v7a5.5 5.5 0 0 1-5.5 5.5h-9A5.5 5.5 0 0 1 2 15.5zM2.6 7.3l8.1 5.2a1.6 1.6 0 0 0 1.7 0l8.1-5.2"/>'
    if [[ -n "$EVENT_URL" ]]; then
      action_html="<a class=\"btn btn--primary\" href=\"$(h "$EVENT_URL")\" target=\"_blank\" rel=\"noopener noreferrer\">Participar online <span aria-hidden=\"true\">↗</span></a>"
    else
      action_html='<span class="btn btn--muted" aria-disabled="true">Modalidad online</span>'
    fi
    location_line="Online"
  else
    mode_label="Evento presencial"
    mode_class="presencial"
    mode_icon='<path d="M12 21s7-6.2 7-11a7 7 0 1 0-14 0c0 4.8 7 11 7 11zM12 10a2.2 2.2 0 1 0 0 4.4A2.2 2.2 0 0 0 12 10z"/>'
    location_line=$(h "$EVENT_LOCATION")
    if [[ -n "$EVENT_MAP_URL" ]]; then
      action_html="<a class=\"btn btn--ghost\" href=\"$(h "$EVENT_MAP_URL")\" target=\"_blank\" rel=\"noopener noreferrer\">Ver en el mapa <span aria-hidden=\"true\">↗</span></a>"
    else
      action_html=''
    fi
  fi

  if [[ "$REGISTER_ENABLED" == true ]]; then
    register_html="<a class=\"btn btn--accent\" href=\"$(h "$REGISTER_URL")\" target=\"_blank\" rel=\"noopener noreferrer\">$(h "$REGISTER_LABEL") <span aria-hidden=\"true\">→</span></a>"
  else
    register_html=''
  fi

  if [[ "$SHOW_EVENT_DETAILS" == true ]]; then
    details_html=$(cat <<DETAILS
        <ul class="facts" id="detalles" aria-label="Detalles del evento">
          <li class="fact">
            <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 6h16v14H4zM4 10h16M8 3v4M16 3v4"/></svg>
            <span data-fecha>$EVENT_DATE</span>
          </li>
          <li class="fact">
            <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 7v5l3 2M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18z"/></svg>
            <span>$EVENT_TIME <small data-tz-label>$EVENT_TIMEZONE</small></span>
          </li>
          <li class="fact">
            <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 21s7-6.2 7-11a7 7 0 1 0-14 0c0 4.8 7 11 7 11zM12 10a2.2 2.2 0 1 0 0 4.4A2.2 2.2 0 0 0 12 10z"/></svg>
            <span>$location_line</span>
          </li>
        </ul>
DETAILS
)
  fi

  if ((render_talks)); then
    for image in "${SLIDER_PATHS[@]}"; do
      i=$((i + 1))
      slide="assets/${image#"$PROJECT_DIR"/assets/}"
      slide_img="<img src=\"$slide\" alt=\"Imagen destacada $i\" loading=\"lazy\" decoding=\"async\">"
      if (( ${WEBP_SLIDER[$((i - 1))]:-0} > 0 )) && [[ "${image,,}" != *.webp ]]; then
        slide_img="<picture><source srcset=\"$(h "$(webp_rel_for "$image")")\" type=\"image/webp\">$slide_img</picture>"
      fi
      slider_html+="          <figure class=\"slide\"><button class=\"slide__open\" type=\"button\" aria-label=\"Ampliar imagen $i\">$slide_img</button></figure>
"
    done
    caption_html='      <p class="section__hint">Usa las flechas, las teclas ← → o desliza para explorar. Toca una imagen para ampliarla.</p>'
  fi
  if [[ -n "$EVENT_END_DATE" ]]; then
    end_date=" data-end-date=\"$EVENT_END_DATE\""
    end_time=" data-end-time=\"$EVENT_END_TIME\""
  fi

  cat > "$file" <<HTML
<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="dark light">
<meta name="description" content="$desc">
<meta name="theme-color" content="#080D12">
<meta name="generator" content="generate.sh">
<title>$title</title>
$favicon
<link rel="stylesheet" href="style.css">
</head>
<body id="inicio" data-interval="$SLIDER_INTERVAL" data-date="$EVENT_DATE" data-time="$EVENT_TIME" data-tz="$EVENT_TIMEZONE"$end_date$end_time data-starting-duration="$EVENT_STARTING_DURATION" data-accent="$(h "$COLOR_ACCENT")" data-secondary="$(h "$COLOR_SECONDARY")" data-background="$(h "$COLOR_BACKGROUND")">

<div class="ambient" aria-hidden="true">
  <span class="orb orb--one"></span>
  <span class="orb orb--two"></span>
  <span class="hex hex--one"></span>
  <span class="hex hex--two"></span>
  <span class="grid"></span>
</div>

<a class="skip" href="#contenido">Saltar al contenido</a>

<header class="nav">
  <div class="wrap nav__inner">
    <a class="brand" href="#inicio"><span class="brand__prompt" aria-hidden="true">&gt;_</span> $name</a>
$(if [[ -n "$nav_html" ]]; then printf '    <nav class="nav__links" aria-label="Navegación principal">\n%s    </nav>\n' "$nav_html"; fi)
  </div>
</header>

<main id="contenido">
  <section class="hero" aria-labelledby="hero-title">
    <div class="wrap hero__grid">
      <div class="hero__copy">
        <span class="badge badge--$mode_class">
          <svg viewBox="0 0 24 24" aria-hidden="true">$mode_icon</svg>
          $mode_label
        </span>
        <h1 id="hero-title">$title</h1>
        <p class="lead">$desc</p>

$details_html

        <div class="actions">
          $register_html
          $action_html
        </div>

        <div class="countdown" data-countdown></div>
        <p class="sr-only" id="countdown-live" aria-live="polite" aria-atomic="true"></p>
      </div>

      <figure class="poster" id="poster">
        <button class="poster__open" type="button" aria-label="Ampliar afiche del evento">
          $poster_open<img id="poster-image" src="$poster_src" alt="$(h "$POSTER_ALT")" width="720" height="960" decoding="async">$poster_close
        </button>
        <figcaption>$(h "$POSTER_ALT")</figcaption>
      </figure>
    </div>
  </section>

$(if ((render_talks)); then cat <<SLIDER
  <section class="section section--talks" id="charlas" aria-labelledby="charlas-title">
    <span class="sr-only" id="destacos"></span>
    <div class="wrap">
      <div class="section__head">
        <p class="eyebrow">Programa</p>
        <h2 id="charlas-title">$talks_title</h2>
      </div>
      <div class="slider" id="slider" role="region" aria-roledescription="carrusel" aria-label="$talks_title" tabindex="0">
        <div class="slider__viewport">
          <div class="slider__track" id="slider-track">
SLIDER
fi)
$slider_html
$(if ((render_talks)); then cat <<'SLIDER'
          </div>
        </div>
        <button class="slider__nav slider__prev" id="slider-prev" type="button" aria-label="Imagen anterior">
          <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M15 5 8 12l7 7"/></svg>
        </button>
        <button class="slider__nav slider__next" id="slider-next" type="button" aria-label="Imagen siguiente">
          <svg viewBox="0 0 24 24" aria-hidden="true"><path d="m9 5 7 7-7 7"/></svg>
        </button>
        <div class="slider__dots" id="slider-dots" role="group" aria-label="Seleccionar imagen"></div>
        <button class="slider__toggle" id="slider-toggle" type="button" aria-pressed="false" aria-label="Pausar reproducción automática">Pausar</button>
        <p class="sr-only" id="slider-live" aria-live="polite" aria-atomic="true"></p>
      </div>
SLIDER
fi)
$caption_html
$(if ((render_talks)); then printf '    </div>\n  </section>\n'; fi)
</main>

<footer class="footer">
  <div class="wrap footer__inner">
    <p><span class="brand__prompt" aria-hidden="true">&gt;_</span> $title</p>
    <p>Hecho con Software Libre · $(h "$EVENT_TIMEZONE")</p>
  </div>
</footer>

<div class="lightbox" id="lightbox" hidden>
  <div class="lightbox__backdrop" data-close></div>
  <div class="lightbox__dialog" role="dialog" aria-modal="true" aria-label="Imagen ampliada">
    <button class="lightbox__btn lightbox__close" id="lightbox-close" type="button" aria-label="Cerrar imagen ampliada">
      <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 6l12 12M18 6 6 18"/></svg>
    </button>
    <button class="lightbox__btn lightbox__prev" id="lightbox-prev" type="button" aria-label="Imagen anterior">
      <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M15 5 8 12l7 7"/></svg>
    </button>
    <button class="lightbox__btn lightbox__next" id="lightbox-next" type="button" aria-label="Imagen siguiente">
      <svg viewBox="0 0 24 24" aria-hidden="true"><path d="m9 5 7 7-7 7"/></svg>
    </button>
    <figure class="lightbox__figure">
      <img id="lightbox-image" alt="" decoding="async">
      <figcaption id="lightbox-caption"></figcaption>
    </figure>
  </div>
</div>

<script src="script.js" defer></script>
</body>
</html>
HTML
}

write_css() {
  cat > "$1" <<'CSS'
/* Identidad fija del afiche HackPoint: verde neón sobre negro azulado. */
:root {
  --color-background: #080D12;
  --color-primary: #00FFA3;
  --color-secondary: #915DF0;
  --color-white: #FFFFFF;
  --color-text: #FFFFFF;
  --color-muted: rgba(255, 255, 255, 0.72);
  --color-glass: rgba(0, 255, 163, 0.045);
  --color-glass-border: rgba(0, 255, 163, 0.22);
  --color-accent: #00FFA3;
  --color-shadow: rgba(0, 0, 0, 0.4);

  /* Alias usados por las reglas existentes. */
  --accent: var(--color-primary);
  --on-accent: var(--color-background);
  --accent-secondary: var(--color-secondary);
  --background: var(--color-background);
  --surface: color-mix(in srgb, var(--color-background) 90%, var(--color-secondary));
  --glass: var(--color-glass);
  --text: var(--color-text);
  --muted: var(--color-muted);
  --border: var(--color-glass-border);
  --shadow: var(--color-shadow);
  --radius: 1.15rem;
  --wrap: 1180px;
  --ease: cubic-bezier(0.22, 1, 0.36, 1);
  --step-0: clamp(1rem, 0.96rem + 0.2vw, 1.1rem);
  --step-1: clamp(1.2rem, 1.08rem + 0.6vw, 1.55rem);
  --step-2: clamp(1.7rem, 1.35rem + 1.6vw, 2.6rem);
  --step-3: clamp(2.4rem, 1.6rem + 3.8vw, 5rem);
}

* { box-sizing: border-box; }
html { scroll-behavior: smooth; scroll-padding-top: 5rem; }
body {
  margin: 0;
  min-width: 320px;
  overflow-x: clip;
  background: var(--background);
  color: var(--text);
  font: var(--step-0)/1.65 system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
  -webkit-font-smoothing: antialiased;
}
body.is-locked { overflow: hidden; }
img, svg { max-width: 100%; }
img { display: block; height: auto; }
a { color: inherit; text-decoration: none; }
button { font: inherit; color: inherit; }
h1, h2 { margin: 0; line-height: 1.08; letter-spacing: -0.035em; text-wrap: balance; }
p { margin: 0; }
ul { margin: 0; padding: 0; list-style: none; }
[hidden] { display: none !important; }
:focus-visible { outline: 3px solid var(--accent); outline-offset: 3px; border-radius: 0.5rem; }
::selection { background: var(--accent); color: var(--background); }

.wrap { width: min(100% - 2.5rem, var(--wrap)); margin-inline: auto; }
.eyebrow {
  margin: 0 0 0.7rem;
  color: var(--accent);
  font: 700 0.8rem/1.2 ui-monospace, monospace;
  letter-spacing: 0.18em;
  text-transform: uppercase;
}
.sr-only {
  position: absolute; width: 1px; height: 1px; padding: 0; margin: -1px;
  overflow: hidden; clip: rect(0, 0, 0, 0); white-space: nowrap; border: 0;
}
.skip {
  position: fixed; z-index: 100; top: 0.6rem; left: 0.6rem;
  padding: 0.65rem 1rem; border-radius: 0.6rem;
  background: var(--text); color: var(--background);
  transform: translateY(-160%); transition: transform 0.2s var(--ease);
}
.skip:focus { transform: none; }

/* Fondo ambiental */
.ambient { position: fixed; inset: 0; z-index: -1; overflow: hidden; pointer-events: none; }
.orb { position: absolute; width: min(60vw, 46rem); aspect-ratio: 1; border-radius: 50%; filter: blur(95px); opacity: 0.3; }
.orb--one { top: -18rem; left: -12rem; background: var(--accent-secondary); }
.orb--two { right: -16rem; bottom: -22rem; background: var(--accent); }
.grid {
  position: absolute; inset: 0;
  background-image: linear-gradient(to right, var(--glass) 1px, transparent 1px),
                    linear-gradient(to bottom, var(--glass) 1px, transparent 1px);
  background-size: 4.5rem 4.5rem;
  mask-image: linear-gradient(to bottom, #000, transparent 75%);
}
/* Geometría hexagonal discreta, inspirada en el afiche. */
.hex {
  position: absolute; aspect-ratio: 1; opacity: 0.5;
  clip-path: polygon(25% 5%, 75% 5%, 100% 50%, 75% 95%, 25% 95%, 0 50%);
  background: linear-gradient(135deg, var(--color-glass), transparent 70%);
  outline: 1px solid var(--color-glass-border);
}
.hex--one { top: 9%; right: 6%; width: min(20vw, 15rem); transform: rotate(12deg); }
.hex--two { bottom: 6%; left: 4%; width: min(16vw, 11rem); transform: rotate(-18deg); background: linear-gradient(135deg, rgba(145, 93, 240, 0.07), transparent 70%); }

/* Navegación */
.nav {
  position: sticky; top: 0; z-index: 30;
  border-bottom: 1px solid var(--border);
  background: color-mix(in srgb, var(--background) 78%, transparent);
  backdrop-filter: blur(18px);
  -webkit-backdrop-filter: blur(18px);
}
.nav__inner { display: flex; align-items: center; justify-content: space-between; gap: 1rem; min-height: 4.4rem; }
.brand { display: inline-flex; align-items: center; gap: 0.6rem; font-weight: 800; letter-spacing: -0.02em; }
.brand__prompt { color: var(--accent); font-family: ui-monospace, monospace; }
.nav__links { display: flex; align-items: center; gap: 0.4rem; }
.nav__links a { padding: 0.55rem 0.85rem; border-radius: 0.6rem; color: var(--muted); font-size: 0.95rem; transition: color 0.2s, background 0.2s; }
.nav__links a:hover, .nav__links a:focus-visible { color: var(--text); background: var(--glass); }

/* Hero */
.hero { padding: clamp(3rem, 7vw, 7rem) 0 clamp(3rem, 6vw, 6rem); }
.hero__grid { display: grid; grid-template-columns: minmax(0, 1.05fr) minmax(0, 0.75fr); gap: clamp(2rem, 5vw, 5rem); align-items: center; }
.badge {
  display: inline-flex; align-items: center; gap: 0.5rem;
  padding: 0.4rem 0.85rem; margin-bottom: 1.5rem;
  border: 1px solid var(--border); border-radius: 999px;
  background: var(--glass); backdrop-filter: blur(12px);
  color: var(--muted); font: 700 0.8rem/1 ui-monospace, monospace; letter-spacing: 0.04em;
}
.badge svg { width: 1.05rem; height: 1.05rem; fill: none; stroke: var(--accent); stroke-width: 1.8; }
.hero h1 { font-size: var(--step-3); max-width: 18ch; }
.lead { max-width: 55ch; margin-top: 1.4rem; color: var(--muted); font-size: var(--step-1); }
.facts { display: flex; flex-wrap: wrap; gap: 0.6rem; margin-top: 2rem; }
.fact {
  display: inline-flex; align-items: center; gap: 0.55rem;
  min-height: 2.8rem; padding: 0.5rem 0.9rem;
  border: 1px solid var(--border); border-radius: 0.8rem;
  background: var(--glass); backdrop-filter: blur(12px);
  font-size: 0.94rem;
}
.fact svg { width: 1.15rem; height: 1.15rem; flex: none; fill: none; stroke: var(--accent); stroke-width: 1.7; }
.fact small { display: block; color: var(--muted); font-size: 0.72rem; }
.actions { display: flex; flex-wrap: wrap; gap: 0.8rem; margin-top: 2rem; }
.btn {
  display: inline-flex; align-items: center; justify-content: center; gap: 0.5rem;
  min-height: 3rem; padding: 0.7rem 1.4rem; border: 1px solid transparent; border-radius: 0.8rem;
  font-weight: 700; cursor: pointer; transition: transform 0.2s var(--ease), filter 0.2s, background 0.2s;
}
.btn:hover { transform: translateY(-2px); filter: brightness(1.08); }
.btn--primary { background: var(--accent-secondary); color: #fff; }
.btn--accent { background: var(--accent); color: var(--on-accent, #08110a); }
.btn--ghost { background: var(--glass); border-color: var(--border); backdrop-filter: blur(12px); }
.btn--muted { background: var(--glass); border-color: var(--border); color: var(--muted); cursor: default; }
.btn--muted:hover { transform: none; filter: none; }
.countdown { display: flex; flex-wrap: wrap; align-items: center; gap: 0.5rem; margin-top: 1.6rem; min-height: 2.6rem; }
.count__lead { align-self: center; margin-right: 0.2rem; color: var(--muted); font: 700 0.8rem/1 ui-monospace, monospace; letter-spacing: 0.12em; text-transform: uppercase; }
.count {
  display: grid; place-items: center; min-width: 4.2rem; padding: 0.4rem 0.6rem;
  border: 1px solid var(--border); border-radius: 0.7rem; background: var(--glass);
}
.count strong { font: 800 1.3rem/1 ui-monospace, monospace; }
.count span { color: var(--muted); font-size: 0.68rem; letter-spacing: 0.1em; text-transform: uppercase; }
.count__done { align-self: center; color: var(--accent); font: 800 0.95rem/1.2 ui-monospace, monospace; letter-spacing: 0.12em; }
.count__done--running { color: var(--accent-secondary); }
.count__done--finished { color: var(--muted); }

/* Afiche */
.poster { margin: 0; }
.poster__open {
  display: block; width: 100%; padding: 0.55rem; border: 1px solid var(--border); border-radius: var(--radius);
  background: var(--glass); backdrop-filter: blur(16px); box-shadow: 0 30px 70px -40px var(--shadow);
  cursor: zoom-in; transition: transform 0.3s var(--ease), border-color 0.3s;
}
.poster__open:hover { transform: translateY(-5px) rotate(-0.6deg); border-color: var(--accent); }
.poster img { width: 100%; height: auto; border-radius: calc(var(--radius) - 0.35rem); }
.poster figcaption { margin-top: 0.9rem; color: var(--muted); font-size: 0.88rem; text-align: center; }

/* Sección y slider */
.section { padding: clamp(2.5rem, 6vw, 5rem) 0; }
.section__head { margin-bottom: 1.8rem; }
.section__head h2 { font-size: var(--step-2); }
.section__hint { margin-top: 1rem; color: var(--muted); font-size: 0.9rem; }
.slider { position: relative; border: 1px solid var(--border); border-radius: var(--radius); background: var(--glass); padding: 0.6rem; }
.slider__viewport { overflow: hidden; border-radius: calc(var(--radius) - 0.4rem); }
.slider__track { display: flex; transition: transform 0.55s var(--ease); will-change: transform; }
.slider__track.is-dragging { transition: none; }
.slide { flex: 0 0 100%; margin: 0; }
.slide__open { display: block; width: 100%; padding: 0; border: 0; background: none; cursor: zoom-in; }
.slide img { width: 100%; aspect-ratio: 16/8; object-fit: cover; border-radius: calc(var(--radius) - 0.4rem); }
.slider__nav, .slider__toggle {
  position: absolute; z-index: 2; border: 1px solid var(--border); border-radius: 999px;
  background: color-mix(in srgb, var(--background) 70%, transparent); backdrop-filter: blur(10px); cursor: pointer;
}
.slider__nav { top: 50%; width: 2.9rem; height: 2.9rem; padding: 0.7rem; transform: translateY(-50%); }
.slider__nav svg { fill: none; stroke: currentColor; stroke-width: 2; }
.slider__prev { left: 1.1rem; }
.slider__next { right: 1.1rem; }
.slider__toggle { right: 1.1rem; bottom: 1.1rem; padding: 0.45rem 0.9rem; font-size: 0.8rem; }
.slider__dots { position: absolute; left: 1.1rem; bottom: 1.1rem; z-index: 2; display: flex; gap: 0.4rem; }
.slider__dots button { width: 1.75rem; height: 1.75rem; padding: 0.5rem; border: 0; border-radius: 50%; background: var(--muted); background-clip: content-box; opacity: 0.45; cursor: pointer; transition: opacity 0.2s, background 0.2s; }
.slider__dots button[aria-current="true"] { background: var(--accent); opacity: 1; transform: scale(1.2); }

/* Footer */
.footer { border-top: 1px solid var(--border); margin-top: 2rem; }
.footer__inner { display: flex; flex-wrap: wrap; justify-content: space-between; gap: 0.6rem; padding: 2rem 0; color: var(--muted); font-size: 0.9rem; }

/* Lightbox */
.lightbox { position: fixed; inset: 0; z-index: 60; display: grid; place-items: center; }
.lightbox__backdrop { position: absolute; inset: 0; background: rgba(3, 6, 16, 0.9); backdrop-filter: blur(8px); }
.lightbox__dialog { position: relative; width: min(94vw, 1100px); }
.lightbox__figure { margin: 0; }
.lightbox__figure img { width: 100%; max-height: 84vh; object-fit: contain; border-radius: 1rem; }
.lightbox__figure figcaption { margin-top: 0.8rem; color: var(--muted); text-align: center; }
.lightbox__btn {
  position: absolute; z-index: 2; display: grid; place-items: center;
  width: 3rem; height: 3rem; padding: 0.75rem;
  border: 1px solid var(--border); border-radius: 50%;
  background: color-mix(in srgb, var(--background) 80%, transparent); cursor: pointer;
}
.lightbox__btn svg { fill: none; stroke: currentColor; stroke-width: 2; }
.lightbox__close { top: -1rem; right: -1rem; }
.lightbox__prev { top: 50%; left: -1rem; transform: translateY(-50%); }
.lightbox__next { top: 50%; right: -1rem; transform: translateY(-50%); }
.lightbox__btn[hidden] { display: none; }

/* Responsive */
@media (max-width: 1080px) {
  :root { --wrap: 1000px; }
  .hero__grid { gap: 2rem; }
  .poster { max-width: 30rem; margin-inline: auto; }
}
@media (max-width: 860px) {
  .hero__grid { grid-template-columns: 1fr; }
  .hero h1 { max-width: 22ch; }
  .poster { max-width: 26rem; }
  .slide img { aspect-ratio: 16/10; }
}
@media (max-width: 640px) {
  :root { --wrap: 100%; }
  .wrap { width: min(100% - 1.75rem, var(--wrap)); }
  .nav__inner { flex-wrap: wrap; justify-content: center; padding-block: 0.6rem; }
  .nav__links { width: 100%; justify-content: center; }
  .hero { padding-top: 2.5rem; }
  .facts { gap: 0.45rem; }
  .fact { min-height: 2.6rem; }
  .btn { min-height: 3rem; padding-inline: 1.1rem; }
  .slider__nav { width: 2.75rem; height: 2.75rem; padding: 0.65rem; }
  .slider__prev { left: 0.7rem; }
  .slider__next { right: 0.7rem; }
  .slide img { aspect-ratio: 4/3; }
  .lightbox__prev { left: 0; }
  .lightbox__next { right: 0; }
  .lightbox__close { top: 0; right: 0; }
}
@media (max-width: 390px) {
  .brand__prompt { display: none; }
  .hero h1 { font-size: clamp(2.1rem, 11vw, 3rem); }
  .count { min-width: 3.6rem; }
}
@media (min-width: 1800px) {
  :root { --wrap: 1400px; }
  .slide img { aspect-ratio: 2/1; }
}
@media (prefers-reduced-motion: reduce) {
  html { scroll-behavior: auto; }
  *, *::before, *::after { animation-duration: 0.01ms !important; transition-duration: 0.01ms !important; }
}
CSS
}

write_js() {
  cat > "$1" <<'JS'
/* Comportamiento: paleta, countdown, slider y lightbox. Sin dependencias. */
(function () {
  "use strict";

  var root = document.documentElement;
  var body = document.body;
  var manual = {
    accent: body.dataset.accent || "",
    secondary: body.dataset.secondary || "",
    background: body.dataset.background || ""
  };

  /* --- Paleta fija: nunca se extraen colores del afiche --- */
  function hexToRgb(hex) {
    var value = String(hex).replace("#", "");
    if (!/^[0-9a-f]{6}$/i.test(value)) return null;
    return [parseInt(value.slice(0, 2), 16), parseInt(value.slice(2, 4), 16), parseInt(value.slice(4, 6), 16)];
  }
  function luminance(hex) {
    var rgb = hexToRgb(hex);
    if (!rgb) return 0;
    var f = function (v) {
      v /= 255;
      return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
    };
    return 0.2126 * f(rgb[0]) + 0.7152 * f(rgb[1]) + 0.0722 * f(rgb[2]);
  }
  function contrast(a, b) {
    var x = luminance(a), y = luminance(b);
    return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05);
  }
  function applyTheme() {
    if (!manual.accent && !manual.secondary && !manual.background) return;
    var accent = manual.accent || "#00FFA3";
    var secondary = manual.secondary || "#915DF0";
    var background = manual.background || "#080D12";
    var values = {
      "--color-primary": accent,
      "--color-secondary": secondary,
      "--color-background": background,
      "--on-accent": contrast(accent, "#000000") >= contrast(accent, "#FFFFFF") ? "#000000" : "#FFFFFF"
    };
    if (contrast("#FFFFFF", background) < 4.5) {
      values["--color-text"] = "#0B1020";
      values["--color-muted"] = "rgba(11, 16, 32, 0.75)";
      values["--color-glass"] = "rgba(11, 16, 32, 0.05)";
      values["--color-glass-border"] = "rgba(11, 16, 32, 0.22)";
    }
    Object.keys(values).forEach(function (key) { root.style.setProperty(key, values[key]); });
  }

  /* --- Countdown --- */
  function zonedNow(tz) {
    var now = new Date();
    if (!tz) return now;
    try {
      var parts = new Intl.DateTimeFormat("en-US", {
        timeZone: tz, year: "numeric", month: "2-digit", day: "2-digit",
        hour: "2-digit", minute: "2-digit", second: "2-digit", hourCycle: "h23"
      }).formatToParts(now).reduce(function (acc, p) { acc[p.type] = p.value; return acc; }, {});
      var hour = parts.hour === "24" ? "00" : parts.hour;
      return new Date(parts.year + "-" + parts.month + "-" + parts.day + "T" + hour + ":" + parts.minute + ":" + parts.second + "Z");
    } catch (error) { return now; }
  }
  function countdown() {
    var holder = document.querySelector("[data-countdown]");
    if (!holder) return;
    var live = document.getElementById("countdown-live");
    var tz = body.dataset.tz;
    var startRaw = body.dataset.date + "T" + body.dataset.time + ":00";
    var start = new Date(tz ? startRaw + "Z" : startRaw).getTime();
    if (!isFinite(start)) return;

    var end = 0;
    if (body.dataset.endDate && body.dataset.endTime) {
      var endRaw = body.dataset.endDate + "T" + body.dataset.endTime + ":00";
      var parsedEnd = new Date(tz ? endRaw + "Z" : endRaw).getTime();
      if (isFinite(parsedEnd) && parsedEnd > start) end = parsedEnd;
    }
    var starting = Number(body.dataset.startingDuration);
    if (!isFinite(starting) || starting < 0) starting = 0;
    var lastAnnouncement = "";

    function announce(text) {
      if (!live || text === lastAnnouncement) return;
      lastAnnouncement = text;
      live.textContent = text;
    }
    function setBoxes(diff) {
      holder.textContent = "";
      var lead = document.createElement("span");
      lead.className = "count__lead";
      lead.textContent = "Faltan";
      holder.appendChild(lead);
      var units = [["días", Math.floor(diff / 86400)], ["horas", Math.floor(diff % 86400 / 3600)],
                   ["min", Math.floor(diff % 3600 / 60)], ["seg", diff % 60]];
      units.forEach(function (unit) {
        var box = document.createElement("div");
        box.className = "count";
        var value = document.createElement("strong");
        var label = document.createElement("span");
        value.textContent = unit[1];
        label.textContent = unit[0];
        box.appendChild(value); box.appendChild(label); holder.appendChild(box);
      });
      announce("Faltan " + units[0][1] + " días, " + units[1][1] + " horas, " + units[2][1] + " minutos");
    }
    function setState(text, modifier) {
      if (holder.firstChild && holder.firstChild.className === "count__done" &&
          holder.firstChild.textContent === text) return;
      holder.textContent = "";
      var done = document.createElement("span");
      done.className = "count__done" + (modifier ? " count__done--" + modifier : "");
      done.textContent = text;
      holder.appendChild(done);
      announce(text);
    }
    function tick() {
      var now = zonedNow(tz).getTime();
      if (!isFinite(now)) return;
      if (end && now >= end) { setState("FIN DEL EVENTO", "finished"); return; }
      if (now < start) { setBoxes(Math.floor((start - now) / 1000)); return; }
      if (now < start + starting * 1000) { setState("INICIANDO"); return; }
      setState("EVENTO EN CURSO", "running");
    }
    tick();
    window.setInterval(tick, 1000);
  }

  /* --- Lightbox --- */
  var lightbox = document.getElementById("lightbox");
  var lbImage = document.getElementById("lightbox-image");
  var lbCaption = document.getElementById("lightbox-caption");
  var lbClose = document.getElementById("lightbox-close");
  var lbPrev = document.getElementById("lightbox-prev");
  var lbNext = document.getElementById("lightbox-next");
  var items = [];
  var current = 0;
  var lastFocus = null;

  function showItem() {
    if (!items.length) return;
    var item = items[current];
    lbImage.src = item.src;
    lbImage.alt = item.alt || "";
    lbCaption.textContent = item.caption || "";
    var multiple = items.length > 1;
    lbPrev.hidden = !multiple;
    lbNext.hidden = !multiple;
  }
  function openLightbox(images, index) {
    items = images.filter(function (item) { return item && item.src; });
    if (!items.length || !lightbox) return;
    current = Math.max(0, Math.min(index || 0, items.length - 1));
    lastFocus = document.activeElement;
    lightbox.hidden = false;
    body.classList.add("is-locked");
    showItem();
    lbClose.focus();
  }
  function closeLightbox() {
    if (!lightbox || lightbox.hidden) return;
    lightbox.hidden = true;
    lbImage.removeAttribute("src");
    lbImage.alt = "";
    lbCaption.textContent = "";
    body.classList.remove("is-locked");
    if (lastFocus && lastFocus.focus) lastFocus.focus();
    lastFocus = null;
  }
  function step(delta) {
    if (!items.length) return;
    current = (current + delta + items.length) % items.length;
    showItem();
  }

  /* --- Slider --- */
  function slider() {
    var rootEl = document.getElementById("slider");
    var track = document.getElementById("slider-track");
    if (!rootEl || !track || !track.children.length) return;
    var slides = Array.prototype.slice.call(track.children);
    var dots = document.getElementById("slider-dots");
    var live = document.getElementById("slider-live");
    var toggle = document.getElementById("slider-toggle");
    var interval = Math.max(1000, Number(body.dataset.interval) || 5000);
    var reduced = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    var index = 0;
    var timer = null;
    var pausedByUser = false;
    var pausedByHover = false;
    var drag = null;

    var images = slides.map(function (slide, i) {
      var img = slide.querySelector("img");
      if (!img) return { src: "", alt: "", caption: "" };
      var caption = slide.querySelector("figcaption");
      return { src: img.currentSrc || img.src, alt: img.alt || "Imagen " + (i + 1), caption: caption ? caption.textContent : "" };
    }).filter(function (item) { return item.src; });

    slides.forEach(function (slide, i) {
      var button = slide.querySelector("button");
      if (button) button.addEventListener("click", function () {
        if (!drag) openLightbox(images, i);
      });
      var img = slide.querySelector("img");
      if (img) img.addEventListener("error", function () { slide.hidden = true; });
      if (dots) {
        var dot = document.createElement("button");
        dot.type = "button";
        dot.setAttribute("aria-label", "Ir a la imagen " + (i + 1));
        dot.addEventListener("click", function () { go(i, true); });
        dots.appendChild(dot);
      }
    });
    if (slides.length < 2) {
      ["slider-prev", "slider-next", "slider-toggle", "slider-dots"].forEach(function (id) {
        var node = document.getElementById(id);
        if (node) node.hidden = true;
      });
    }

    function canPlay() {
      return !reduced && slides.length > 1 && !pausedByUser && !pausedByHover && !document.hidden;
    }
    function stop() { if (timer !== null) { clearInterval(timer); timer = null; } }
    function start() {
      stop();
      if (canPlay()) timer = setInterval(function () { go(index + 1, false); }, interval);
    }
    function go(position, manual) {
      index = (position + slides.length) % slides.length;
      track.style.transform = "translateX(" + (-index * 100) + "%)";
      if (dots) Array.prototype.forEach.call(dots.children, function (dot, i) {
        if (i === index) dot.setAttribute("aria-current", "true");
        else dot.removeAttribute("aria-current");
      });
      if (live) live.textContent = "Imagen " + (index + 1) + " de " + slides.length;
      if (toggle) {
        toggle.textContent = pausedByUser ? "Reanudar" : "Pausar";
        toggle.setAttribute("aria-pressed", pausedByUser ? "true" : "false");
        toggle.setAttribute("aria-label", pausedByUser ? "Reanudar reproducción automática" : "Pausar reproducción automática");
      }
      if (manual) start();
    }

    var prev = document.getElementById("slider-prev");
    var next = document.getElementById("slider-next");
    if (prev) prev.addEventListener("click", function () { go(index - 1, true); });
    if (next) next.addEventListener("click", function () { go(index + 1, true); });
    if (toggle) toggle.addEventListener("click", function () { pausedByUser = !pausedByUser; start(); go(index, false); });
    rootEl.addEventListener("mouseenter", function () { pausedByHover = true; start(); });
    rootEl.addEventListener("mouseleave", function () { pausedByHover = false; start(); });
    rootEl.addEventListener("focusin", function () { pausedByHover = true; start(); });
    rootEl.addEventListener("focusout", function (event) {
      if (!rootEl.contains(event.relatedTarget)) { pausedByHover = false; start(); }
    });
    rootEl.addEventListener("keydown", function (event) {
      if (event.key === "ArrowLeft") { event.preventDefault(); go(index - 1, true); }
      else if (event.key === "ArrowRight") { event.preventDefault(); go(index + 1, true); }
      else if (event.key === "Home") { event.preventDefault(); go(0, true); }
      else if (event.key === "End") { event.preventDefault(); go(slides.length - 1, true); }
    });
    document.addEventListener("visibilitychange", start);

    var viewport = track.parentElement;
    viewport.addEventListener("pointerdown", function (event) {
      if (event.pointerType === "mouse" && event.button !== 0) return;
      drag = { x: event.clientX };
      track.classList.add("is-dragging");
    });
    window.addEventListener("pointermove", function (event) {
      if (!drag) return;
      var dx = event.clientX - drag.x;
      if (Math.abs(dx) > 6) track.style.transform = "translateX(calc(" + (-index * 100) + "% + " + dx + "px))";
    });
    window.addEventListener("pointerup", function (event) {
      if (!drag) return;
      var dx = event.clientX - drag.x;
      drag = null;
      track.classList.remove("is-dragging");
      if (Math.abs(dx) > 45) go(index + (dx < 0 ? 1 : -1), true);
      else go(index, false);
    });
    window.addEventListener("pointercancel", function () {
      drag = null;
      track.classList.remove("is-dragging");
      go(index, false);
    });
    go(0, false);
    start();
  }

  /* --- Cableado --- */
  if (lbClose) lbClose.addEventListener("click", closeLightbox);
  if (lbPrev) lbPrev.addEventListener("click", function () { step(-1); });
  if (lbNext) lbNext.addEventListener("click", function () { step(1); });
  if (lightbox) lightbox.addEventListener("click", function (event) {
    if (event.target.hasAttribute("data-close")) closeLightbox();
  });
  document.addEventListener("keydown", function (event) {
    if (!lightbox || lightbox.hidden) return;
    if (event.key === "Escape") { event.preventDefault(); closeLightbox(); }
    else if (event.key === "ArrowLeft") { event.preventDefault(); step(-1); }
    else if (event.key === "ArrowRight") { event.preventDefault(); step(1); }
    else if (event.key === "Tab") {
      var focusables = [lbClose, lbPrev, lbNext].filter(function (node) { return node && !node.hidden; });
      if (!focusables.length) return;
      var first = focusables[0], last = focusables[focusables.length - 1];
      if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
      else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
    }
  });

  var posterButton = document.querySelector(".poster__open");
  if (posterButton) {
    var posterImage = document.getElementById("poster-image");
    posterButton.addEventListener("click", function () {
      openLightbox([{ src: posterImage.currentSrc || posterImage.src, alt: posterImage.alt, caption: "" }], 0);
    });
  }

  applyTheme();
  countdown();
  slider();
})();
JS
}

build() {
  prepare_webp
  mkdir -p -- "$BUILD_DIR/assets/slider" || die "no se pudo crear el directorio de construcción"
  mkdir -p -- "$(dirname -- "$BUILD_DIR/assets/${POSTER#assets/}")" ||
    die "no se pudo crear el directorio del afiche"
  cp -- "$POSTER_PATH" "$BUILD_DIR/assets/${POSTER#assets/}" || die "no se pudo copiar el afiche"
  if ((WEBP_POSTER)); then
    mkdir -p -- "$(dirname -- "$BUILD_DIR/$(webp_rel_for "$POSTER")")" ||
      die "no se pudo crear el directorio del afiche WebP"
    cp -- "$(webp_cache_for "$POSTER_PATH")" "$BUILD_DIR/$(webp_rel_for "$POSTER")" ||
      die "no se pudo copiar el afiche WebP"
  fi
  if (( ${#SLIDER_PATHS[@]} > 0 )); then
    local image rel i=0
    for image in "${SLIDER_PATHS[@]}"; do
      rel=${image#"$PROJECT_DIR"/assets/}
      mkdir -p -- "$(dirname -- "$BUILD_DIR/assets/$rel")" ||
        die "no se pudo crear el directorio de: $rel"
      cp -- "$image" "$BUILD_DIR/assets/$rel" || die "no se pudo copiar: $rel"
      if (( ${WEBP_SLIDER[$i]:-0} > 0 )); then
        mkdir -p -- "$(dirname -- "$BUILD_DIR/$(webp_rel_for "$image")")" ||
          die "no se pudo crear el directorio WebP de: $rel"
        cp -- "$(webp_cache_for "$image")" "$BUILD_DIR/$(webp_rel_for "$image")" ||
          die "no se pudo copiar la versión WebP de: $rel"
      fi
      i=$((i + 1))
    done
  fi
  if [[ -f "$PROJECT_DIR/assets/favicon.png" ]]; then
    cp -- "$PROJECT_DIR/assets/favicon.png" "$BUILD_DIR/assets/favicon.png" ||
      die "no se pudo copiar el favicon"
    if ((WEBP_FAVICON)); then
      cp -- "$(webp_cache_for "$PROJECT_DIR/assets/favicon.png")" "$BUILD_DIR/assets/favicon.webp" ||
        die "no se pudo copiar el favicon WebP"
    fi
  fi

  write_html "$BUILD_DIR/index.html"
  write_css "$BUILD_DIR/style.css"
  write_js "$BUILD_DIR/script.js"

  [[ -s "$BUILD_DIR/index.html" && -s "$BUILD_DIR/style.css" && -s "$BUILD_DIR/script.js" ]] ||
    die "la salida generada está incompleta"
  grep -q '<title>' "$BUILD_DIR/index.html" || die "index.html no tiene título"

  if [[ -n "$CNAME_NAME" ]]; then
    echo "$CNAME_NAME" > "$BUILD_DIR/CNAME"
  fi
}

publish() {
  if [[ -e "$OUTPUT_ABS" ]]; then
    rm -rf -- "$OUTPUT_ABS" || die "no se pudo limpiar $OUTPUT_ABS"
  fi
  mv -- "$BUILD_DIR" "$OUTPUT_ABS" || die "no se pudo publicar en $OUTPUT_ABS"
  BUILD_DIR=""
}

main() {
  parse_args "$@"
  validate

  if ((CHECK_ONLY)); then
    log "validación correcta; no se escribió salida"
    exit 0
  fi

  BUILD_DIR="$PROJECT_DIR/.build.$$"
  trap 'if [[ -n "$BUILD_DIR" && -d "$BUILD_DIR" ]]; then rm -rf -- "$BUILD_DIR"; fi' EXIT

  build

  if ((DRY_RUN)); then
    log "simulación correcta; $OUTPUT_ABS no fue modificado"
  else
    publish
    log "sitio generado correctamente en $OUTPUT_ABS"
  fi

  log "evento:      $EVENT_NAME"
  log "modalidad:   $EVENT_MODE"
  log "inicio:      $EVENT_DATE $EVENT_TIME ($EVENT_TIMEZONE)"
  log "fin:         ${EVENT_END_DATE:-sin fecha de fin} ${EVENT_END_TIME:-}"
  log "afiche:      $POSTER"
  log "slider:      ${#SLIDER_PATHS[@]} imágenes"
  log "detalles:    $SHOW_EVENT_DETAILS"
  log "charlas:     $SHOW_TALKS ($SECTION_TALKS_TITLE)"
  log "registro:    $REGISTER_ENABLED"
  log "assets:      $ASSET_COUNT"
}

main "$@"
