# CLAUDE.md - ExifCli (exiftool-cli)

## Project Overview

**Name:** ExifCli  
**Type:** CLI Tool (Python)  
**Description:** CLI tool for extracting, exporting, and removing EXIF metadata from photos. Supports interactive menu mode with native macOS file picker, batch processing, and multiple export formats.  
**Owner:** @polidisio  

## Tech Stack

- **Language:** Python 3.9+
- **Dependencies:** Pillow, piexif, click, colorama
- **Platform:** macOS/Linux
- **Build:** setuptools (pyproject.toml)

## Quick Start

```bash
# Install from source
pip install -e .

# Interactive mode
exiftool-cli

# Extract EXIF
exiftool-cli extract photo.jpg

# Export to JSON
exiftool-cli export photo.jpg -o output.json

# Export to CSV
exiftool-cli export photo.jpg -o output.csv

# Remove EXIF (preserves image quality)
exiftool-cli remove photo.jpg -o clean_photo.jpg

# Keep GPS only
exiftool-cli remove photo.jpg --keep-gps -o clean_photo.jpg

# Batch process folder
exiftool-cli batch --folder /path/to/photos --extract
exiftool-cli batch --folder /path/to/photos --recursive --remove
```

## File Structure

```
ExifCli/
├── src/
│   └── exiftool_cli/           # Main package
├── tests/                       # Pytest tests
├── Formula/                     # Homebrew formula
├── homebrew-tap/               # Homebrew tap repo
├── pyproject.toml
├── MANPAGE.md
├── README.md
└── CLAUDE.md
```

## Features

| Feature | Description |
|---------|-------------|
| Interactive Mode | Menu-driven with macOS file picker |
| Extract | Display metadata in readable table |
| Export | JSON or CSV format |
| Remove | Strip EXIF preserving quality |
| Batch | Process entire folders with progress |

## Supported Formats

- JPEG (.jpg, .jpeg)
- PNG (.png)
- TIFF (.tif, .tiff)

## Conventions

- Entry point: `exiftool_cli.cli:main`
- Package location: `src/exiftool_cli/`
- Tests: pytest in `tests/` directory

## Testing

```bash
# Run all tests
pytest tests/ -v

# Run with coverage
pytest tests/ --cov=src/exiftool_cli --cov-report=html

# Dev install with test deps
pip install -e ".[dev]"
```

## Homebrew Installation

```bash
brew install polidisio/tap/exiftool-cli
```

## Important Rules

### ✅ Always Do
- Preserve image quality when removing EXIF
- Test on real photos before release
- Keep piexif compatible with target formats

### ❌ Never Do
- Modify EXIF in place (always output to new file)
- Commit test photos to repo

## Resources

- Homebrew tap: `https://github.com/polidisio/homebrew-tap`
- Token optimization tips: `shared/claude-optimization-tips.md` (Obsidian Vault)

---

**Owner:** Jose Maudisio (@polidisio)  
**Last updated:** 2026-04-24

---

---

## Workflow

### Para tareas simples
Sé directo: "Añade validación al form" — no necesitas explicar contexto.

### Para tareas complejas (>3 pasos)
1. Agent propone plan primero
2. Usuario confirma
3. Agent ejecuta
4. Agent verifica con tests

### Para cada tarea
1. **Plan** → Si son >3 pasos, escribir en `tasks/todo.md`
2. **Verify** → Confirmar antes de cambios grandes
3. **Execute** → Cambio más pequeño posible
4. **Test** → Ejecutar tests, verificar regression
5. **Document** → Actualizar si es necesario

---

## Code Quality

### SIEMPRE
- Código legible y mantenible
- Seguir convenciones del proyecto
- DRY — no duplicar lógica
- Validar input antes de procesar

### NUNCA
- Hardcodear credenciales o tokens
- "Hacky fixes" sin justificación
- Duplicar código sin razón
- Commits sin mensaje descriptivo

---

## Security

- **NUNCA hardcodear** credenciales — usar environment variables
- **NUNCA exponer** tokens en logs o errores
- **Validar input** antes de procesar
- Si hay secrets, usar `.env` y nunca commitearlo

---

## Self-Improvement

### Si cometes un error
1. Documentar en `lessons.md` — qué salió mal, por qué, cómo evitarlo
2. Actualizar este archivo si la convención no estaba clara
3. No repetir

### Si descubres algo útil
- Documentar en notas del proyecto
- Compartir con Jose si es relevante

---

## Token Optimization

### Hacer
- Agrupar múltiples requests en uno
- Editar en vez de reply (menos historial)
- Nuevo tema = nueva conversación
- Planificar en chat, construir en workspace

### Evitar
- Subir carpetas enteras — solo archivos necesarios
- Múltiples prompts cortos seguidos
- Usar Opus para tareas simples
- Mantener contexto irrelevante

**Budget:** ~88% de tokens en conversaciones largas = solo historial. Mantenerlo limpio.

---

## Resources

**Obsidian Vault:** `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/Saraiba/`

| Recurso | Ubicación en Vault |
|---------|---------------------|
| Best practices | `shared/coding-best-practices.md` |
| Optimization tips | `shared/claude-optimization-tips.md` |
| Skills docs | `shared/openclw-skills.md` |
| Guía coding agents | `shared/guia-coding-agents.md` |

---

## Contact

**Jose Maudisio** — @polidisio
**Issues:** Abrir en GitHub o preguntar en Telegram
