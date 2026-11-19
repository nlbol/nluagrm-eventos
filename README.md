# Generador de landing pages para eventos

Un único script Bash (`generate.sh`) que genera una landing page estática, moderna y responsive para un evento. Sin backend, sin frameworks, sin Python, sin Node y sin dependencias externas.

La salida es un sitio estático listo para GitHub Pages, Netlify o cualquier hosting de archivos.

## Requisitos

- Bash 5 o superior.
- Herramientas estándar de Linux: `cp`, `mkdir`, `mv`, `rm`, `grep`, `date`.
- Un navegador moderno para ver el resultado.

No hay nada que instalar.

## Estructura

```
generate.sh              Configuración + generador
assets/
  poster.svg             Afiche del evento
  logo.svg               Logo (opcional)
  favicon.png            Favicon (opcional)
  slider/01.svg ...      Imágenes adicionales
public/                  Sitio generado (se regenera en cada ejecución)
  index.html
  style.css
  script.js
  assets/
```

## Configuración

Edita el bloque **CONFIGURACIÓN DEL EVENTO** al inicio de `generate.sh`:

```bash
EVENT_NAME="DebianDay Bolivia 2026"
EVENT_DESCRIPTION="Charlas, talleres e instalación asistida."
EVENT_DATE="2026-12-12"
EVENT_TIME="09:00"
EVENT_TIMEZONE="America/La_Paz"

EVENT_MODE="presencial"          # presencial | online
EVENT_LOCATION="Santa Cruz de la Sierra, Bolivia"
EVENT_MAP_URL="https://www.openstreetmap.org/..."
EVENT_URL=""                     # solo para online

REGISTER_ENABLED=true
REGISTER_URL="https://example.org/registro"
REGISTER_LABEL="Registrarme"

POSTER="assets/poster.svg"
POSTER_ALT="Afiche del evento"

SLIDER_IMAGES=(
  "assets/slider/01.svg"
  "assets/slider/02.svg"
)
SLIDER_INTERVAL=5000             # milisegundos (1000-120000)

OUTPUT_DIR="public"
```

### Afiche

Coloca tu imagen en `assets/` y ajusta `POSTER`. Se admiten `png`, `jpg`, `jpeg`, `webp`, `svg`, `avif` y `gif`. El afiche se muestra sin deformar, se puede ampliar con clic o teclado y es la imagen que más influye en la paleta de colores. No uses rutas absolutas ni `..`.

### Slider

Agrega o quita rutas en `SLIDER_IMAGES`. Funciona con cero, una o varias imágenes:

- Rotación automática configurable con `SLIDER_INTERVAL`.
- Botones anterior/siguiente, indicadores y pausa.
- Teclado: `←`, `→`, `Inicio`, `Fin` cuando el carrusel tiene el foco.
- Swipe táctil y arrastre con ratón.
- Se pausa al interactuar, al enfocar y cuando la pestaña no está visible.
- Respeta `prefers-reduced-motion`.

Para desactivarlo sin borrar la lista: `./generate.sh --no-slider`.

### Modalidad

- `EVENT_MODE="presencial"`: muestra el badge «Evento presencial», la dirección y, si `EVENT_MAP_URL` está definida, un botón «Ver en el mapa».
- `EVENT_MODE="online"`: muestra el badge «Evento online» y un botón «Participar online» hacia `EVENT_URL`. Si no hay URL, avisa durante la generación y muestra la modalidad sin enlace.

Nunca se muestran ambas modalidades a la vez.

### Registro

Con `REGISTER_ENABLED=true` se genera el botón hacia `REGISTER_URL` con el texto `REGISTER_LABEL`. Con `false` no se genera ningún enlace ni espacio reservado.

### Fecha, hora y zona horaria

`EVENT_DATE` usa `AAAA-MM-DD`, `EVENT_TIME` usa `HH:MM` (24 horas) y `EVENT_TIMEZONE` es un identificador como `America/La_Paz` o `Europe/Madrid`. Se muestra un contador regresivo; cuando llega la hora cambia a «El evento ya comenzó». Si la zona no es válida, se usa la hora local del navegador.

### Colores

Por defecto, `script.js` extrae los colores dominantes del afiche con Canvas y genera una paleta legible (contraste mínimo 4.5:1). Si quieres fijar colores manuales:

```bash
COLOR_ACCENT="#a3e635"
COLOR_SECONDARY="#4f7cff"
COLOR_BACKGROUND="#0a0f1d"
```

Deja una variable vacía para seguir derivando ese color del afiche.

## Uso

```bash
./generate.sh                    # genera en public/
./generate.sh --help             # ayuda
./generate.sh --check            # solo valida
./generate.sh --dry-run          # valida y construye sin publicar
./generate.sh --output public    # directorio de salida
./generate.sh --event "Otro nombre"
./generate.sh --poster assets/otro-afiche.svg
./generate.sh --mode online
./generate.sh --no-slider
./generate.sh --slider-interval 8000
```

La salida se construye en un directorio temporal dentro del proyecto y se publica de forma atómica. Si algo falla, se informa en stderr y el directorio temporal se elimina. El directorio de salida debe estar dentro del proyecto y no puede ser `assets/` ni `.git/`.

## Verificación

```bash
bash -n generate.sh
./generate.sh --check
./generate.sh
```

Para ver el sitio en local:

```bash
busybox httpd -f -p 127.0.0.1:8123 -h public
# abre http://127.0.0.1:8123/
```

También sirve `python3 -m http.server 8123 --directory public` si lo prefieres, aunque el proyecto no lo requiere.

## GitHub Pages

El repositorio incluye `.github/workflows/build-pages.yml`:

1. Sube el repositorio a GitHub.
2. En **Settings → Pages**, elige **GitHub Actions** como fuente.
3. Cada push a `main` genera y publica `public/` automáticamente.

Si prefieres publicar sin Actions, ejecuta `./generate.sh` y commitea el contenido de `public/`, luego elige **Deploy from a branch** con la rama `main` y carpeta `/public`.

## Seguridad y accesibilidad

- `set -Eeuo pipefail`, comillas en todas las variables, sin `eval`.
- Validación de fechas, horas, URLs, modos, rutas, symlinks y formatos de imagen.
- Todo el texto se escapa antes de escribir HTML.
- HTML semántico, navegación por teclado, foco visible, ARIA en slider y lightbox, `alt` en imágenes, `reduced-motion` y objetivos táctiles amplios.
- Paleta con contraste verificado; Lighthouse: accesibilidad, buenas prácticas y SEO en 1.00.
