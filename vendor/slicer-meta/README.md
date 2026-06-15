<div align="center">

# Slicer Meta Parser

A TypeScript library for parsing metadata from 3D printing slicer files

[![npm version](https://img.shields.io/badge/npm-1.1.0-blue.svg)](https://www.npmjs.com/package/@parallel-7/slicer-meta)
[![Node.js Version](https://img.shields.io/badge/node-%3E%3D18-brightgreen.svg)](https://nodejs.org)
[![TypeScript](https://img.shields.io/badge/TypeScript-5.5-blue.svg)](https://www.typescriptlang.org/)
[![License](https://img.shields.io/badge/license-Private-red.svg)](https://github.com/Parallel-7/slicer-meta)

</div>

---

<div align="center">

## Quick Start

</div>

Add the GitHub Packages registry to `.npmrc` in your project root:

```
@parallel-7:registry=https://npm.pkg.github.com/
```

Install the package:

```bash
npm install @parallel-7/slicer-meta
```

> You will need to authenticate with GitHub Packages to install private packages.

Use the `parseSlicerFile` function — it automatically handles all supported formats:

```typescript
import { parseSlicerFile } from '@parallel-7/slicer-meta';

const metadata = await parseSlicerFile('path/to/your/file.gcode');

console.log('Slicer:', metadata.slicer);
console.log('File info:', metadata.file);

if (metadata.threeMf) {
  console.log('3MF data:', metadata.threeMf);
}
```

---

<div align="center">

## Features

</div>

- **Three file formats** — G-Code (`.gcode`, `.g`), FlashForge binary (`.gx`), and 3MF archives (`.3mf`)
- **Four slicers detected** — FlashPrint, Orca-FlashForge, OrcaSlicer, and Legacy GX, identified from file headers
- **Thumbnail extraction** — Base64 thumbnails from G-Code and 3MF; binary thumbnails from GX files
- **Filament tracking** — Usage in mm, meters, and grams; per-filament color and type for multi-material prints
- **3MF-specific data** — Support detection, plate preview images, and model file names from the archive
- **Single unified API** — `parseSlicerFile` dispatches to the right parser automatically; individual parsers also exported for direct use

---

<div align="center">

## API

</div>

<div align="center">

| Parser | File Types | Notes |
|--------|-----------|-------|
| `GCodeParser` | `.gcode`, `.g` | Auto-detects FlashPrint vs Orca-FlashForge vs OrcaSlicer |
| `FlashPrintParser` | `.gcode` | FlashPrint-specific files |
| `OrcaFlashForgeParser` | `.gcode` | Orca-FlashForge files |
| `GXParser` | `.gx` | FlashForge binary format |
| `ThreeMfParser` | `.3mf` | 3MF archives (optimized for OrcaSlicer) |

</div>

For full return type definitions (Slicer Metadata, File Metadata, 3MF Specific Data), see [docs/api.md](docs/api.md).

For per-parser examples and multi-filament usage, see [docs/usage.md](docs/usage.md).

---

<div align="center">

## Development

</div>

```bash
npm run build   # compile TypeScript
npm test        # run tests
```
