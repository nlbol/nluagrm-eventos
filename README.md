# Generador de landing pages para eventos

Un único script Bash (`generate.sh`) que genera una landing page estática, moderna y responsive para un evento. Sin backend, sin frameworks, sin Python, sin Node y sin dependencias externas.

La salida es un sitio estático listo para GitHub Pages, Netlify o cualquier hosting de archivos.

## Requisitos

- Bash 5 o superior.
- Herramientas estándar de Linux: `cp`, `mkdir`, `mv`, `rm`, `grep`, `date`, `file`.
- Opcional para WebP: `cwebp`, ImageMagick (`magick`/`convert`) o `ffmpeg` con libwebp.

Sin herramienta WebP el sitio se genera igual, sirviendo los originales.

## Estructura

```
generate.sh              Configuración + generador
assets/
  poster.png             Afiche del evento
  logo.svg               Logo (opcional)
  favicon.png            Favicon (opcional)
  slider/01.png ...      Imágenes de charlas y participantes
public/                  Sitio generado (se regenera en cada ejecución)
  index.html
  style.css
  script.js
  assets/                Originales + versiones WebP cuando están disponibles
.webp-cache/             Caché WebP ignorada por Git; no se publica
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

POSTER="assets/poster.png"
POSTER_ALT="Afiche del evento"

SLIDER_IMAGES=(
  "assets/slider/01.png"
  "assets/slider/02.png"
)
SLIDER_INTERVAL=5000             # milisegundos (1000-120000)

SHOW_EVENT_DETAILS=true
SHOW_TALKS=true
SECTION_TALKS_TITLE="Charlas y participantes"

EVENT_END_DATE=""                # AAAA-MM-DD; vacío = sin fin
EVENT_END_TIME=""                # HH:MM; vacío = 23:59
EVENT_STARTING_DURATION=300      # segundos del estado INICIANDO

CONVERT_WEBP=true
WEBP_QUALITY=82
WEBP_LOSSLESS=false
WEBP_INSTALL_TOOLS=false

OUTPUT_DIR="public"
CNAME_NAME="eventos.nluagrm.org"
```

### Afiche

Coloca tu imagen en `assets/` y ajusta `POSTER`. Se admiten `png`, `jpg`, `jpeg`, `webp`, `svg`, `avif` y `gif`. El afiche se muestra sin deformar y se puede ampliar con clic o teclado. La identidad visual no cambia cuando cambia el afiche. No uses rutas absolutas ni `..`.

### Detalles del evento

`SHOW_EVENT_DETAILS=true` muestra la lista de fecha, hora y lugar y su enlace en la navegación. Con `false` no se renderiza el bloque ni el enlace. El contador sigue funcionando de forma independiente.

### Charlas y participantes

`SHOW_TALKS=true` muestra las fichas de `SLIDER_IMAGES` y su enlace de navegación. El título se configura con `SECTION_TALKS_TITLE` y aparece en el encabezado, la navegación y la etiqueta accesible del carrusel. Con `false` no se genera la sección ni su enlace. Es independiente de `SHOW_EVENT_DETAILS`.

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

`EVENT_DATE` usa `AAAA-MM-DD`, `EVENT_TIME` usa `HH:MM` (24 horas) y `EVENT_TIMEZONE` es un identificador válido como `America/La_Paz`. El inicio es absoluto y no depende del reloj del visitante.

`EVENT_END_DATE` y `EVENT_END_TIME` son opcionales. El contador tiene cuatro estados:

1. Antes del inicio: «Faltan» con días, horas, minutos y segundos.
2. Desde el inicio durante `EVENT_STARTING_DURATION` segundos: «INICIANDO».
3. Hasta la hora final (o sin límite si no se configura): «EVENTO EN CURSO».
4. Al alcanzar la hora final: «FIN DEL EVENTO».

Una fecha final anterior al inicio se rechaza durante la validación.

### Colores

Paleta fija inspirada en el afiche HackPoint, centralizada en `public/style.css`:

```css
--color-background: #080D12;   --color-primary: #00FFA3;
--color-secondary: #915DF0;   --color-text: #FFFFFF;
--color-muted: rgba(255,255,255,0.72);
--color-glass: rgba(0,255,163,0.045);
--color-glass-border: rgba(0,255,163,0.22);
```

No se extraen colores del afiche en tiempo de ejecución. Si necesitas otros colores, sobrescribe manualmente:

```bash
COLOR_ACCENT="#00FFA3"
COLOR_SECONDARY="#915DF0"
COLOR_BACKGROUND="#080D12"
```

Deja una variable vacía para conservar el valor de la identidad.

### Optimización WebP

Con `CONVERT_WEBP=true`, el generador convierte el afiche, las imágenes de charlas y el favicon si hay una herramienta disponible, en este orden: `cwebp`, ImageMagick y `ffmpeg` con libwebp. El HTML usa `<picture>` con WebP y mantiene el original como fallback; los originales nunca se modifican. Las copias se guardan en `.webp-cache/` y se reutilizan si son más recientes que el original (idempotente). Los SVG se sirven tal cual.

Calidad por defecto: `WEBP_QUALITY=82` (1-100). Para gráficos que requieren exactitud, `WEBP_LOSSLESS=true` ignora la calidad.

Si no hay herramienta, se informa el gestor de paquetes según el sistema (`apt`, `dnf`, `yum`, `pacman`, `zypper` o `apk`) y se continúa sin conversión. Ejemplos de instalación manual:

```bash
sudo apt install webp
sudo dnf install libwebp-tools
sudo pacman -S libwebp
```

El script nunca usa `sudo` automáticamente. Para proponer una instalación interactiva, activa `WEBP_INSTALL_TOOLS=true`; sin terminal o sin confirmación no instala nada.

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

## GitHub Pages

El repositorio incluye `.github/workflows/build-pages.yml`:

1. Sube el repositorio a GitHub.
2. En **Settings → Pages**, elige **GitHub Actions** como fuente.
3. Cada push a `main` genera y publica `public/` automáticamente.

Si prefieres publicar sin Actions, ejecuta `./generate.sh` y commitea el contenido de `public/`, luego elige **Deploy from a branch** con la rama `main` y carpeta `/public`.

## Seguridad y accesibilidad

- `set -Eeuo pipefail`, comillas en todas las variables, sin `eval`.
- Validación de fechas, horas, zona horaria, URLs, modos, switches, rutas, symlinks y formatos de imagen.
- Todo el texto se escapa antes de escribir HTML; sin `eval` ni instalaciones silenciosas.
- HTML semántico, navegación por teclado, foco visible, ARIA en slider, lightbox y countdown, `alt` en imágenes, `reduced-motion` y objetivos táctiles amplios.
- Paleta fija con contraste verificado.
