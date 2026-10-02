# VisualizadorGC

App nativa de macOS para **leer y escribir Markdown y texto plano** de forma rápida. Swift + AppKit, sin dependencias.

## Qué hace

- **Tres vistas** (selector arriba a la derecha): **Preview** (formateado y editable), **Markdown** (crudo, con colores y números de línea) y **Split** (ambos lado a lado).
- **Preview editable**: se puede escribir y borrar texto directamente; los símbolos de Markdown no se aceptan ahí (para eso está la vista Markdown). Casillas `- [ ]` se marcan con un clic.
- **Código con colores**: JS/TS, Python, SQL, JSON, YAML, Prisma, bash (comandos en verde), diff y HTML. Botón para copiar cada bloque.
- **Pestañas** en una misma ventana, o ventana nueva aparte.
- **Panel lateral**: índice de títulos y árbol de archivos de una carpeta.
- **Abrir**: arrastrar un `.md`/`.txt` a la ventana o al Dock, `⌘P` por nombre, o abrir una carpeta. Enlaces relativos entre `.md` (`⌘-clic`).
- **Exportar** a PDF o HTML, búsqueda con `⌘F`, ruta del archivo siempre visible.

## Instalar (sin Xcode)

Requisitos: **macOS 13 o superior** (Intel o Apple Silicon). No hace falta Xcode ni Swift.

1. Descarga [`VisualizadorGC-macOS.zip`](https://github.com/giancode1/md_visualizer_simply/releases/latest/download/VisualizadorGC-macOS.zip) desde [Releases](https://github.com/giancode1/md_visualizer_simply/releases/latest).
2. Descomprímelo y mueve `VisualizadorGC.app` a *Aplicaciones*.
3. La primera vez macOS la bloqueará porque no está notarizada por Apple: clic derecho sobre la app › *Abrir* (en macOS 15: *Ajustes del Sistema › Privacidad y seguridad › Abrir de todos modos*). También sirve en Terminal: `xattr -dr com.apple.quarantine /Applications/VisualizadorGC.app`.

## Compilar desde el código

Requisitos: macOS 13+ y **Xcode o Command Line Tools** (Swift 5.9+).

```bash
./build.sh
open VisualizadorGC.app
```

`build.sh` firma la app con tu certificado *Apple Development* si lo encuentra y, si no, usa firma ad-hoc.

## Atajos

| Atajo | Acción |
| --- | --- |
| `⌘O` / `⌘⇧O` | Abrir archivo / abrir carpeta |
| `⌘P` | Abrir rápido por nombre |
| `⌘N` `⌘T` / `⌘⇧N` | Nueva pestaña / nueva ventana |
| `⌘1` `⌘2` `⌘3` | Preview / Markdown / Split |
| `⌘B` | Panel lateral |
| `⌘F` | Buscar |
| `⌘S` | Guardar (también se guarda solo) |

## Notas

- La carpeta de trabajo y el panel lateral no se recuerdan entre sesiones: cada arranque empieza limpio.
- Verificación rápida del renderizado: `.build/release/VisualizadorGC --selftest` imprime `ok`.
