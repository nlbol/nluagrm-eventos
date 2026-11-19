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

POSTER="assets/poster.svg"
POSTER_ALT="Afiche de HackPoint 2026"

SLIDER_IMAGES=(
  "assets/slider/01.svg"
  "assets/slider/02.svg"
  "assets/slider/03.svg"
)
SLIDER_INTERVAL=5000

OUTPUT_DIR="public"
CNAME_NAME="eventos.nluagrm.org"

# Colores manuales opcionales. Dejar vacío para derivarlos del afiche.
# Ejemplo: COLOR_ACCENT="#a3e635"
COLOR_ACCENT=""
COLOR_SECONDARY=""
COLOR_BACKGROUND=""

# ============================================================
# FIN DE LA CONFIGURACIÓN
# ============================================================

VERSION="2.0.0"
DRY_RUN=0
CHECK_ONLY=0
NO_SLIDER=0
PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
BUILD_DIR=""
OUTPUT_ABS=""
ASSET_COUNT=0

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

validate() {
  [[ -n "$EVENT_NAME" ]] || die "EVENT_NAME está vacío"
  [[ -n "$EVENT_DESCRIPTION" ]] || die "EVENT_DESCRIPTION está vacío"
  valid_date "$EVENT_DATE" || die "EVENT_DATE debe ser una fecha válida AAAA-MM-DD: $EVENT_DATE"
  [[ $EVENT_TIME =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]] ||
    die "EVENT_TIME debe tener formato HH:MM: $EVENT_TIME"
  [[ "$EVENT_MODE" == presencial || "$EVENT_MODE" == online ]] ||
    die "EVENT_MODE debe ser 'presencial' u 'online': $EVENT_MODE"
  [[ $SLIDER_INTERVAL =~ ^[0-9]+$ ]] &&
    ((10#$SLIDER_INTERVAL >= 1000 && 10#$SLIDER_INTERVAL <= 120000)) ||
    die "SLIDER_INTERVAL debe ser un entero entre 1000 y 120000"

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
  local action_html register_html poster_src poster_rel caption slider_html='' slide
  local caption_html='' i=0 favicon=''

  title=$(h "$EVENT_NAME")
  desc=$(h "$EVENT_DESCRIPTION")
  name=$(h "${EVENT_NAME%% *}")
  poster_rel=${POSTER#assets/}
  poster_src="assets/$poster_rel"

  favicon=''
  if [[ -f "$PROJECT_DIR/assets/favicon.png" ]]; then
    favicon='<link rel="icon" type="image/png" href="assets/favicon.png">'
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

  if (( ${#SLIDER_PATHS[@]} > 0 )); then
    for image in "${SLIDER_PATHS[@]}"; do
      i=$((i + 1))
      slide="assets/${image#"$PROJECT_DIR"/assets/}"
      slider_html+="          <figure class=\"slide\"><button class=\"slide__open\" type=\"button\" aria-label=\"Ampliar imagen $i\"><img src=\"$slide\" alt=\"Imagen destacada $i\" loading=\"lazy\" decoding=\"async\"></button></figure>
"
    done
    caption_html='      <p class="section__hint">Usa las flechas, las teclas ← → o desliza para explorar. Toca una imagen para ampliarla.</p>'
  fi

  cat > "$file" <<HTML
<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="dark light">
<meta name="description" content="$desc">
<meta name="theme-color" content="#0b1020">
<meta name="generator" content="generate.sh">
<title>$title</title>
$favicon
<link rel="stylesheet" href="style.css">
</head>
<body id="inicio" data-interval="$SLIDER_INTERVAL" data-date="$EVENT_DATE" data-time="$EVENT_TIME" data-tz="$EVENT_TIMEZONE" data-accent="$(h "$COLOR_ACCENT")" data-secondary="$(h "$COLOR_SECONDARY")" data-background="$(h "$COLOR_BACKGROUND")">

<div class="ambient" aria-hidden="true">
  <span class="orb orb--one"></span>
  <span class="orb orb--two"></span>
  <span class="grid"></span>
</div>

<a class="skip" href="#contenido">Saltar al contenido</a>

<header class="nav">
  <div class="wrap nav__inner">
    <a class="brand" href="#inicio"><span class="brand__prompt" aria-hidden="true">&gt;_</span> $name</a>
    <nav class="nav__links" aria-label="Navegación principal">
      <a href="#detalles">Detalles</a>
      <a href="#destacos">Galería</a>
    </nav>
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

        <ul class="facts" id="detalles">
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

        <div class="actions">
          $register_html
          $action_html
        </div>

        <div class="countdown" data-countdown aria-live="polite"></div>
      </div>

      <figure class="poster" id="poster">
        <button class="poster__open" type="button" aria-label="Ampliar afiche del evento">
          <img id="poster-image" src="$poster_src" alt="$(h "$POSTER_ALT")" width="720" height="960" decoding="async">
        </button>
        <figcaption>$(h "$POSTER_ALT")</figcaption>
      </figure>
    </div>
  </section>

$(if (( ${#SLIDER_PATHS[@]} > 0 )); then cat <<'SLIDER'
  <section class="section" id="destacos" aria-labelledby="destacos-title">
    <div class="wrap">
      <div class="section__head">
        <p class="eyebrow">Galería</p>
        <h2 id="destacos-title">Momentos para recordar</h2>
      </div>
      <div class="slider" id="slider" role="region" aria-roledescription="carrusel" aria-label="Imágenes destacadas" tabindex="0">
        <div class="slider__viewport">
          <div class="slider__track" id="slider-track">
SLIDER
fi)
$slider_html
$(if (( ${#SLIDER_PATHS[@]} > 0 )); then cat <<'SLIDER'
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
$(if (( ${#SLIDER_PATHS[@]} > 0 )); then printf '    </div>\n  </section>\n'; fi)
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
/* Estilos base. Los colores se ajustan desde script.js según el afiche. */
:root {
  --accent: #a3e635;
  --on-accent: #08110a;
  --accent-secondary: #4f7cff;
  --background: #0a0f1d;
  --surface: #121a2e;
  --glass: rgba(255, 255, 255, 0.07);
  --text: #f4f7ff;
  --muted: #a9b4cf;
  --border: rgba(255, 255, 255, 0.14);
  --shadow: rgba(2, 6, 18, 0.55);
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
.countdown { display: flex; flex-wrap: wrap; gap: 0.5rem; margin-top: 1.6rem; min-height: 2.6rem; }
.count {
  display: grid; place-items: center; min-width: 4.2rem; padding: 0.4rem 0.6rem;
  border: 1px solid var(--border); border-radius: 0.7rem; background: var(--glass);
}
.count strong { font: 800 1.3rem/1 ui-monospace, monospace; }
.count span { color: var(--muted); font-size: 0.68rem; letter-spacing: 0.1em; text-transform: uppercase; }
.count__done { align-self: center; color: var(--accent); font-weight: 700; }

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

  /* --- Paleta derivada del afiche --- */
  function hexToRgb(hex) {
    var value = String(hex).replace("#", "");
    if (!/^[0-9a-f]{6}$/i.test(value)) return null;
    return [parseInt(value.slice(0, 2), 16), parseInt(value.slice(2, 4), 16), parseInt(value.slice(4, 6), 16)];
  }
  function rgbToHex(r, g, b) {
    var part = function (n) { return Math.max(0, Math.min(255, Math.round(n))).toString(16).padStart(2, "0"); };
    return "#" + part(r) + part(g) + part(b);
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
  function mix(a, b, amount) {
    var x = hexToRgb(a) || [80, 120, 255];
    var y = hexToRgb(b) || [10, 15, 30];
    return rgbToHex(x[0] + (y[0] - x[0]) * amount, x[1] + (y[1] - x[1]) * amount, x[2] + (y[2] - x[2]) * amount);
  }
  function saturation(hex) {
    var rgb = hexToRgb(hex);
    if (!rgb) return 0;
    var max = Math.max(rgb[0], rgb[1], rgb[2]);
    var min = Math.min(rgb[0], rgb[1], rgb[2]);
    return max ? (max - min) / max : 0;
  }
  function rgbToHsl(rgb) {
    var r = rgb[0] / 255, g = rgb[1] / 255, b = rgb[2] / 255;
    var max = Math.max(r, g, b), min = Math.min(r, g, b), delta = max - min;
    var l = (max + min) / 2, h = 0, s = 0;
    if (delta) {
      s = l > 0.5 ? delta / (2 - max - min) : delta / (max + min);
      if (max === r) h = ((g - b) / delta + (g < b ? 6 : 0)) / 6;
      else if (max === g) h = ((b - r) / delta + 2) / 6;
      else h = ((r - g) / delta + 4) / 6;
    }
    return [h, s, l];
  }
  function hslToHex(h, s, l) {
    function channel(n) {
      var k = (n + h * 12) % 12;
      return l - s * Math.min(l, 1 - l) * Math.max(-1, Math.min(k - 3, 9 - k, 1));
    }
    return rgbToHex(channel(0) * 255, channel(8) * 255, channel(4) * 255);
  }
  // Aclara manteniendo tono y saturación hasta lograr contraste legible.
  function readable(color, background, target) {
    var rgb = hexToRgb(color);
    if (!rgb) return color;
    var hsl = rgbToHsl(rgb);
    var sat = Math.max(0.45, hsl[1]);
    var candidate = color;
    for (var l = hsl[2]; l <= 0.95; l += 0.04) {
      candidate = hslToHex(hsl[0], sat, l);
      if (contrast(candidate, background) >= target) return candidate;
    }
    return candidate;
  }
  function applyPalette(p) {
    var background = p.background;
    var text = contrast("#ffffff", background) >= contrast("#101525", background) ? "#ffffff" : "#101525";
    var accent = readable(p.accent, background, 4.5);
    var onAccent = contrast(accent, "#08110a") >= 4.5 ? "#08110a" : "#ffffff";
    var secondary = readable(p.secondary, background, 2.2);
    for (var i = 0; i < 12 && contrast("#ffffff", secondary) < 4.5; i++) {
      secondary = mix(secondary, "#000000", 0.08);
    }
    var values = {
      "--accent": accent,
      "--on-accent": onAccent,
      "--accent-secondary": secondary,
      "--background": background,
      "--surface": mix(background, p.secondary, 0.12),
      "--text": text,
      "--muted": mix(text, background, 0.38),
      "--border": text === "#ffffff" ? "rgba(255,255,255,0.14)" : "rgba(16,26,52,0.14)",
      "--glass": text === "#ffffff" ? "rgba(255,255,255,0.07)" : "rgba(255,255,255,0.62)",
      "--shadow": text === "#ffffff" ? "rgba(2,6,18,0.55)" : "rgba(31,45,84,0.16)"
    };
    Object.keys(values).forEach(function (key) { root.style.setProperty(key, values[key]); });
  }
  function fallbackPalette() {
    return { accent: "#a3e635", secondary: "#4f7cff", background: "#0a0f1d" };
  }
  function sampleImage(image) {
    return new Promise(function (resolve) {
      try {
        var canvas = document.createElement("canvas");
        canvas.width = 40; canvas.height = 40;
        var ctx = canvas.getContext("2d", { willReadFrequently: true });
        if (!ctx) return resolve([]);
        ctx.drawImage(image, 0, 0, 40, 40);
        var data = ctx.getImageData(0, 0, 40, 40).data;
        var buckets = new Map();
        for (var i = 0; i < data.length; i += 16) {
          if (data[i + 3] < 200) continue;
          var key = Math.round(data[i] / 32) + "," + Math.round(data[i + 1] / 32) + "," + Math.round(data[i + 2] / 32);
          var entry = buckets.get(key);
          if (entry) { entry.n++; entry.r += data[i]; entry.g += data[i + 1]; entry.b += data[i + 2]; }
          else buckets.set(key, { n: 1, r: data[i], g: data[i + 1], b: data[i + 2] });
        }
        resolve(Array.from(buckets.values()).sort(function (a, b) { return b.n - a.n; })
          .map(function (e) { return { hex: rgbToHex(e.r / e.n, e.g / e.n, e.b / e.n), n: e.n }; }));
      } catch (error) { resolve([]); }
    });
  }
  function loadTheme() {
    var base = fallbackPalette();
    if (manual.accent || manual.secondary || manual.background) {
      applyPalette({
        accent: manual.accent || base.accent,
        secondary: manual.secondary || base.secondary,
        background: manual.background || base.background
      });
      return Promise.resolve();
    }
    applyPalette(base);
    var image = document.getElementById("poster-image");
    if (!image) return Promise.resolve();
    function derive() {
      return sampleImage(image).then(function (colors) {
        if (!colors.length) return;
        var primary = colors[0].hex;
        var candidates = colors.slice(0, 14).filter(function (c) { return c.n >= 2; });
        var vivid = candidates.slice().sort(function (a, b) {
          return saturation(b.hex) * Math.sqrt(b.n) - saturation(a.hex) * Math.sqrt(a.n);
        })[0];
        var secondary = (colors.slice(0, 10).find(function (c) {
          return c.hex !== primary && contrast(c.hex, primary) > 1.3;
        }) || {}).hex || base.secondary;
        applyPalette({
          accent: vivid ? vivid.hex : base.accent,
          secondary: secondary,
          background: mix(primary, "#070b16", 0.9)
        });
      });
    }
    if (image.complete && image.naturalWidth) return derive();
    return new Promise(function (resolve) {
      image.addEventListener("load", function () { derive().then(resolve); }, { once: true });
      image.addEventListener("error", resolve, { once: true });
    });
  }

  /* --- Countdown --- */
  function zonedNow(tz) {
    var now = new Date();
    if (!tz) return now;
    try {
      var parts = new Intl.DateTimeFormat("en-US", {
        timeZone: tz, year: "numeric", month: "2-digit", day: "2-digit",
        hour: "2-digit", minute: "2-digit", second: "2-digit", hour12: false
      }).formatToParts(now).reduce(function (acc, p) { acc[p.type] = p.value; return acc; }, {});
      return new Date(parts.year + "-" + parts.month + "-" + parts.day + "T" + parts.hour + ":" + parts.minute + ":" + parts.second + "Z");
    } catch (error) { return now; }
  }
  function countdown() {
    var holder = document.querySelector("[data-countdown]");
    if (!holder) return;
    var raw = body.dataset.date + "T" + body.dataset.time + ":00";
    var target = new Date(body.dataset.tz ? raw + "Z" : raw).getTime();
    if (!isFinite(target)) return;
    function tick() {
      var diff = Math.floor((target - zonedNow(body.dataset.tz).getTime()) / 1000);
      if (diff <= 0) {
        holder.textContent = "";
        var done = document.createElement("span");
        done.className = "count__done";
        done.textContent = "El evento ya comenzó";
        holder.appendChild(done);
        return;
      }
      var units = [["días", Math.floor(diff / 86400)], ["horas", Math.floor(diff % 86400 / 3600)],
                   ["min", Math.floor(diff % 3600 / 60)], ["seg", diff % 60]];
      if (holder.children.length !== units.length) {
        holder.textContent = "";
        units.forEach(function (unit) {
          var box = document.createElement("div");
          box.className = "count";
          var value = document.createElement("strong");
          var label = document.createElement("span");
          label.textContent = unit[0];
          box.appendChild(value); box.appendChild(label); holder.appendChild(box);
        });
      }
      units.forEach(function (unit, index) { holder.children[index].firstChild.textContent = unit[1]; });
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
      return { src: img.src, alt: img.alt || "Imagen " + (i + 1), caption: caption ? caption.textContent : "" };
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
      openLightbox([{ src: posterImage.src, alt: posterImage.alt, caption: "" }], 0);
    });
  }

  loadTheme();
  countdown();
  slider();
})();
JS
}

build() {
  mkdir -p -- "$BUILD_DIR/assets/slider" || die "no se pudo crear el directorio de construcción"
  cp -- "$POSTER_PATH" "$BUILD_DIR/assets/${POSTER#assets/}" || die "no se pudo copiar el afiche"
  if (( ${#SLIDER_PATHS[@]} > 0 )); then
    local image rel
    for image in "${SLIDER_PATHS[@]}"; do
      rel=${image#"$PROJECT_DIR"/assets/}
      cp -- "$image" "$BUILD_DIR/assets/$rel" || die "no se pudo copiar: $rel"
    done
  fi
  if [[ -f "$PROJECT_DIR/assets/favicon.png" ]]; then
    cp -- "$PROJECT_DIR/assets/favicon.png" "$BUILD_DIR/assets/favicon.png" ||
      die "no se pudo copiar el favicon"
  fi

  write_html "$BUILD_DIR/index.html"
  write_css "$BUILD_DIR/style.css"
  write_js "$BUILD_DIR/script.js"

  [[ -s "$BUILD_DIR/index.html" && -s "$BUILD_DIR/style.css" && -s "$BUILD_DIR/script.js" ]] ||
    die "la salida generada está incompleta"
  grep -q '<title>' "$BUILD_DIR/index.html" || die "index.html no tiene título"

  echo "$CNAME_NAME" > "$BUILD_DIR/CNAME"

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
  log "fecha:       $EVENT_DATE $EVENT_TIME ($EVENT_TIMEZONE)"
  log "afiche:      $POSTER"
  log "slider:      ${#SLIDER_PATHS[@]} imágenes"
  log "registro:    $REGISTER_ENABLED"
  log "assets:      $ASSET_COUNT"
}

main "$@"
