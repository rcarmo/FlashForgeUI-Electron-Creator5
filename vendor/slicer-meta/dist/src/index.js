/**
 * @fileoverview Runtime entry point for the vendored slicer metadata parser.
 *
 * Provides a compact parser for G-code, GX, and 3MF job files used by
 * FlashForgeUI's job uploader. The public surface intentionally mirrors the
 * private @parallel-7/slicer-meta package consumed by the app.
 */

const fs = require('node:fs');
const path = require('node:path');
const AdmZip = require('adm-zip');
const { XMLParser } = require('fast-xml-parser');

const IMAGE_EXTENSIONS = new Set(['.png', '.jpg', '.jpeg']);

async function parseSlicerFile(filePath) {
  if (!filePath || typeof filePath !== 'string') {
    throw new Error('filePath must be a string');
  }

  const extension = path.extname(filePath).toLowerCase();

  if (extension === '.3mf') {
    return parseThreeMfFile(filePath);
  }

  if (extension === '.gcode' || extension === '.g' || extension === '.gx') {
    return parseGcodeFile(filePath);
  }

  throw new Error(`Unsupported slicer file type: ${extension || 'unknown'}`);
}

function parseGcodeFile(filePath) {
  const buffer = fs.readFileSync(filePath);
  const text = decodeMostlyText(buffer);
  const fileInfo = createBaseFileInfo(filePath, buffer.length);
  const comments = collectCommentMetadata(text);
  const filaments = extractFilaments(comments, text);
  const slicer = extractSlicerInfo(comments, text);
  const thumbnail = extractGcodeThumbnail(text);

  return {
    file: {
      ...fileInfo,
      printerModel: firstValue(comments, ['machine_type', 'printer_model', 'printer', 'printable_area']),
      filamentType: filaments[0]?.type || firstValue(comments, ['filament_type', 'filament_settings_id']),
      filamentUsedMM: firstNumber(comments, [
        'filament_used_mm',
        'filament used [mm]',
        'total filament used [mm]',
        'filament_length',
      ]),
      filamentUsedG: firstNumber(comments, ['filament_used_g', 'filament used [g]', 'total filament used [g]']),
      filaments,
      thumbnail,
      layerHeight: firstNumber(comments, ['layer_height', 'layer height']),
      infill: firstNumber(comments, ['sparse_infill_density', 'infill', 'fill_density']),
      layers: firstInteger(comments, ['layer_count', 'total layer number', 'total_layer_count']),
    },
    slicer,
  };
}

function parseThreeMfFile(filePath) {
  const zip = new AdmZip(filePath);
  const entries = zip.getEntries();
  const textEntries = entries
    .filter((entry) => !entry.isDirectory && isTextEntry(entry.entryName))
    .map((entry) => ({
      name: entry.entryName,
      text: entry.getData().toString('utf8'),
    }));
  const combinedText = textEntries.map((entry) => entry.text).join('\n');
  const comments = collectCommentMetadata(combinedText);
  const xmlData = parseXmlEntries(textEntries);
  const filaments = extractFilaments(comments, combinedText, xmlData);
  const plateImage = extractPlateImage(entries);
  const fileInfo = createBaseFileInfo(filePath, fs.statSync(filePath).size);
  const slicer = extractSlicerInfo(comments, combinedText, xmlData);
  const threeMf = {
    printerModelId: firstValue(comments, ['printer_model', 'printer_model_id', 'machine_start_gcode']) || findXmlValue(xmlData, [
      'printer_model',
      'printer_model_id',
    ]),
    supportUsed: /support/i.test(firstValue(comments, ['support_material', 'enable_support']) || ''),
    filaments,
    plateImage,
    layerHeight: firstNumber(comments, ['layer_height', 'layer height']) || findXmlNumber(xmlData, ['layer_height']),
    infill: firstNumber(comments, ['sparse_infill_density', 'infill', 'fill_density']) || findXmlNumber(xmlData, ['infill']),
    layerCount: firstInteger(comments, ['layer_count', 'total layer number']) || findXmlNumber(xmlData, ['layer_count']),
    firstLayerTime: firstNumber(comments, ['first_layer_time']),
    warnings: extractWarnings(combinedText),
  };

  return {
    file: {
      ...fileInfo,
      printerModel: threeMf.printerModelId,
      filamentType: filaments[0]?.type,
      filaments,
      thumbnail: plateImage,
      layerHeight: threeMf.layerHeight,
      infill: threeMf.infill,
      layers: threeMf.layerCount,
    },
    slicer,
    threeMf,
  };
}

function createBaseFileInfo(filePath, fileSize) {
  return {
    fileName: path.basename(filePath),
    filePath,
    fileSize,
  };
}

function decodeMostlyText(buffer) {
  const nulIndex = buffer.indexOf(0);
  const textBuffer = nulIndex >= 0 ? buffer.subarray(nulIndex + 1) : buffer;
  return textBuffer.toString('utf8');
}

function collectCommentMetadata(text) {
  const map = new Map();
  for (const rawLine of text.split(/\r?\n/)) {
    const line = rawLine.trim().replace(/^;+/, '').trim();
    if (!line) continue;

    const separator = line.includes('=') ? '=' : line.includes(':') ? ':' : null;
    if (!separator) continue;

    const index = line.indexOf(separator);
    const key = normalizeKey(line.slice(0, index));
    const value = line.slice(index + 1).trim();
    if (!key || !value) continue;

    if (!map.has(key)) {
      map.set(key, []);
    }
    map.get(key).push(value);
  }
  return map;
}

function extractSlicerInfo(comments, text, xmlData = []) {
  const generatedBy =
    firstValue(comments, ['generated by', 'generated_by']) || matchFirst(text, /generated by\s+([^;\r\n]+)/i);
  const slicerName =
    firstValue(comments, ['slicer', 'slicer_name']) || parseSlicerName(generatedBy) || findXmlValue(xmlData, ['slicer']);
  const slicerVersion =
    firstValue(comments, ['slicer_version']) || parseSlicerVersion(generatedBy) || findXmlValue(xmlData, ['slicer_version']);

  return {
    slicerName,
    slicerVersion,
    sliceDate: firstValue(comments, ['date', 'slice_date', 'print_time']),
    sliceTime: firstValue(comments, ['time', 'slice_time']),
    printEta:
      firstValue(comments, [
        'estimated printing time',
        'estimated printing time (normal mode)',
        'estimated_printing_time',
        'print_eta',
      ]) || formatSeconds(firstNumber(comments, ['estimated_printing_time_seconds', 'print_time'])),
  };
}

function extractFilaments(comments, text, xmlData = []) {
  const types = splitList(
    firstValue(comments, ['filament_type', 'filament_types', 'filament_settings_id']) || findXmlValue(xmlData, ['filament_type'])
  );
  const colors = splitList(
    firstValue(comments, ['filament_colour', 'filament_color', 'extruder_colour']) || findXmlValue(xmlData, ['filament_colour'])
  );
  const usedMm = splitNumberList(firstValue(comments, ['filament used [mm]', 'filament_used_mm', 'filament_length']));
  const usedG = splitNumberList(firstValue(comments, ['filament used [g]', 'filament_used_g', 'total filament used [g]']));
  const xmlFilaments = findXmlFilaments(xmlData);
  const count = Math.max(types.length, colors.length, usedMm.length, usedG.length, xmlFilaments.length, 0);
  const filaments = [];

  for (let index = 0; index < count; index += 1) {
    const xmlFilament = xmlFilaments[index] || {};
    const usedMmValue = usedMm[index] ?? xmlFilament.usedMM;
    const usedGValue = usedG[index] ?? xmlFilament.usedG;
    filaments.push({
      type: types[index] || xmlFilament.type || 'Unknown',
      color: normalizeColor(colors[index] || xmlFilament.color),
      usedMM: numberToString(usedMmValue),
      usedM: numberToString(typeof usedMmValue === 'number' ? usedMmValue / 1000 : undefined),
      usedG: numberToString(usedGValue),
    });
  }

  if (filaments.length === 0) {
    const legacyLength = firstNumber(comments, ['filament_used_mm', 'filament used [mm]']);
    const legacyWeight = firstNumber(comments, ['filament_used_g', 'filament used [g]']);
    const legacyType = firstValue(comments, ['filament_type']);
    if (legacyLength || legacyWeight || legacyType) {
      filaments.push({
        type: legacyType || 'Unknown',
        color: undefined,
        usedMM: numberToString(legacyLength),
        usedM: numberToString(typeof legacyLength === 'number' ? legacyLength / 1000 : undefined),
        usedG: numberToString(legacyWeight),
      });
    }
  }

  return filaments;
}

function parseXmlEntries(entries) {
  const parser = new XMLParser({
    ignoreAttributes: false,
    attributeNamePrefix: '',
    allowBooleanAttributes: true,
  });

  const parsed = [];
  for (const entry of entries) {
    try {
      parsed.push({ name: entry.name, data: parser.parse(entry.text) });
    } catch {
      // Ignore malformed auxiliary files; metadata is best effort.
    }
  }
  return parsed;
}

function findXmlFilaments(xmlData) {
  const filaments = [];
  for (const { data } of xmlData) {
    visit(data, (value) => {
      if (!value || typeof value !== 'object') return;
      const type = readObjectValue(value, ['filament_type', 'type', 'material']);
      const color = readObjectValue(value, ['filament_colour', 'filament_color', 'color']);
      const usedMM = toNumber(readObjectValue(value, ['used_mm', 'filament_used_mm', 'used_length']));
      const usedG = toNumber(readObjectValue(value, ['used_g', 'filament_used_g', 'weight']));
      if (type || color || usedMM || usedG) {
        filaments.push({ type, color, usedMM, usedG });
      }
    });
  }
  return filaments;
}

function findXmlValue(xmlData, keys) {
  for (const { data } of xmlData) {
    let found;
    visit(data, (value, key) => {
      if (found || !key) return;
      if (keys.includes(normalizeKey(key)) && typeof value !== 'object') {
        found = String(value);
      }
    });
    if (found) return found;
  }
  return undefined;
}

function findXmlNumber(xmlData, keys) {
  return toNumber(findXmlValue(xmlData, keys));
}

function visit(value, callback, key) {
  callback(value, key);
  if (Array.isArray(value)) {
    for (const item of value) visit(item, callback, key);
    return;
  }
  if (value && typeof value === 'object') {
    for (const [childKey, childValue] of Object.entries(value)) {
      visit(childValue, callback, childKey);
    }
  }
}

function readObjectValue(object, keys) {
  for (const [key, value] of Object.entries(object)) {
    if (!keys.includes(normalizeKey(key))) continue;
    if (value === undefined || value === null || typeof value === 'object') continue;
    return String(value);
  }
  return undefined;
}

function extractPlateImage(entries) {
  const imageEntry =
    entries.find((entry) => !entry.isDirectory && /plate/i.test(entry.entryName) && IMAGE_EXTENSIONS.has(path.extname(entry.entryName).toLowerCase())) ||
    entries.find((entry) => !entry.isDirectory && /thumbnail|preview/i.test(entry.entryName) && IMAGE_EXTENSIONS.has(path.extname(entry.entryName).toLowerCase()));

  return imageEntry ? imageEntry.getData().toString('base64') : undefined;
}

function extractGcodeThumbnail(text) {
  const match = text.match(/;\s*thumbnail\s+begin[^\n]*\n([\s\S]*?);\s*thumbnail\s+end/i);
  if (!match) return undefined;
  return match[1]
    .split(/\r?\n/)
    .map((line) => line.replace(/^;\s?/, '').trim())
    .join('');
}

function extractWarnings(text) {
  const warnings = [];
  for (const match of text.matchAll(/(?:warning|warn)[^:\n]*:\s*([^\r\n<]+)/gi)) {
    warnings.push({ level: 1, message: match[1].trim(), msg: match[1].trim() });
  }
  return warnings;
}

function isTextEntry(name) {
  const extension = path.extname(name).toLowerCase();
  return extension === '.xml' || extension === '.model' || extension === '.config' || extension === '.gcode' || extension === '.txt';
}

function firstValue(map, keys) {
  for (const key of keys) {
    const values = map.get(normalizeKey(key));
    if (values?.[0]) return values[0];
  }
  return undefined;
}

function firstNumber(map, keys) {
  for (const key of keys) {
    const values = map.get(normalizeKey(key));
    if (!values) continue;
    for (const value of values) {
      const number = toNumber(value);
      if (number !== undefined) return number;
    }
  }
  return undefined;
}

function firstInteger(map, keys) {
  const number = firstNumber(map, keys);
  return number === undefined ? undefined : Math.round(number);
}

function splitList(value) {
  if (!value) return [];
  return value
    .split(/[;,]/)
    .map((item) => item.trim())
    .filter(Boolean);
}

function splitNumberList(value) {
  if (!value) return [];
  return value
    .split(/[;,]/)
    .map((item) => toNumber(item))
    .filter((item) => item !== undefined);
}

function normalizeKey(key) {
  return String(key).trim().toLowerCase().replace(/^;+/, '').replace(/\s+/g, ' ').replace(/-/g, '_');
}

function normalizeColor(color) {
  if (!color) return undefined;
  const trimmed = String(color).trim();
  if (/^#[0-9a-f]{6}$/i.test(trimmed)) return trimmed;
  if (/^[0-9a-f]{6}$/i.test(trimmed)) return `#${trimmed}`;
  return trimmed;
}

function toNumber(value) {
  if (value === undefined || value === null) return undefined;
  const match = String(value).match(/-?\d+(?:\.\d+)?/);
  if (!match) return undefined;
  const number = Number(match[0]);
  return Number.isFinite(number) ? number : undefined;
}

function numberToString(value) {
  if (typeof value !== 'number' || !Number.isFinite(value)) return undefined;
  return String(value);
}

function parseSlicerName(value) {
  if (!value) return undefined;
  const match = String(value).match(/^(.*?)(?:\s+v?\d+(?:\.\d+)*)?$/);
  return match?.[1]?.trim() || undefined;
}

function parseSlicerVersion(value) {
  if (!value) return undefined;
  return matchFirst(String(value), /\bv?(\d+(?:\.\d+)+(?:[-+][\w.]+)?)\b/i);
}

function matchFirst(text, regex) {
  const match = text.match(regex);
  return match?.[1]?.trim();
}

function formatSeconds(seconds) {
  if (seconds === undefined) return undefined;
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  const secs = Math.round(seconds % 60);
  if (hours > 0) return `${hours}h ${minutes}m ${secs}s`;
  if (minutes > 0) return `${minutes}m ${secs}s`;
  return `${secs}s`;
}

exports.parseSlicerFile = parseSlicerFile;
exports.GCodeParser = { parse: parseGcodeFile };
exports.FlashPrintParser = { parse: parseGcodeFile };
exports.OrcaFlashForgeParser = { parse: parseGcodeFile };
exports.OrcaSlicerParser = { parse: parseGcodeFile };
exports.GXParser = { parse: parseGcodeFile };
exports.ThreeMfParser = { parse: parseThreeMfFile };
