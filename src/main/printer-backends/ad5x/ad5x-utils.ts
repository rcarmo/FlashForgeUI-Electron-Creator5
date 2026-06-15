/**
 * @fileoverview AD5X utility functions for type guards, validation, and material station operations.
 *
 * Provides centralized utility functions for AD5X printer operations:
 * - Type guards for AD5X-specific data structures
 * - Material compatibility validation
 * - Material station status extraction and transformation
 * - Multi-color job detection
 * - Job validation and analysis
 *
 * Key exports:
 * - isAD5XJobInfo(): Type guard for AD5X job detection
 * - isMultiColorJob(): Detect if job requires material station
 * - validateMaterialCompatibility(): Check tool-slot material matching
 * - extractMaterialStationStatus(): Extract and transform material station from machine info
 *
 * This module centralizes logic previously scattered across multiple dialog files,
 * providing a single source of truth for AD5X-specific validation and extraction logic.
 * Used by AD5XBackend and material-related dialogs for consistent material management.
 */

import { createEmptyMaterialStation, transformMaterialStation } from './ad5x-transforms.js';
import { AD5XJobInfo, isAD5XMachineInfo, MaterialStationStatus, MatlStationInfo, SlotInfo } from './ad5x-types.js';

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null;
}

function getObjectField(source: Record<string, unknown>, ...keys: string[]): Record<string, unknown> | null {
  for (const key of keys) {
    const value = source[key];
    if (isRecord(value)) {
      return value;
    }
  }
  return null;
}

function getArrayField(source: Record<string, unknown>, ...keys: string[]): unknown[] {
  for (const key of keys) {
    const value = source[key];
    if (Array.isArray(value)) {
      return value;
    }
  }
  return [];
}

function getStringField(source: Record<string, unknown>, fallback: string, ...keys: string[]): string {
  for (const key of keys) {
    const value = source[key];
    if (typeof value === 'string') {
      return value;
    }
  }
  return fallback;
}

function getNumberField(source: Record<string, unknown>, fallback: number, ...keys: string[]): number {
  for (const key of keys) {
    const value = source[key];
    if (typeof value === 'number' && Number.isFinite(value)) {
      return value;
    }
    if (typeof value === 'string' && value.trim() !== '') {
      const parsed = Number(value);
      if (Number.isFinite(parsed)) {
        return parsed;
      }
    }
  }
  return fallback;
}

function getBooleanField(source: Record<string, unknown>, fallback: boolean, ...keys: string[]): boolean {
  for (const key of keys) {
    const value = source[key];
    if (typeof value === 'boolean') {
      return value;
    }
    if (typeof value === 'number') {
      return value !== 0;
    }
    if (typeof value === 'string') {
      const normalized = value.trim().toLowerCase();
      if (['1', 'true', 'yes', 'open'].includes(normalized)) {
        return true;
      }
      if (['0', 'false', 'no', 'close', 'closed'].includes(normalized)) {
        return false;
      }
    }
  }
  return fallback;
}

function normalizeSlotInfo(slot: unknown, index: number): SlotInfo {
  const slotRecord = isRecord(slot) ? slot : {};
  const hasFilament = getBooleanField(slotRecord, false, 'hasFilament', 'HasFilament');

  return {
    slotId: getNumberField(slotRecord, index + 1, 'slotId', 'SlotId'),
    hasFilament,
    materialName: getStringField(slotRecord, '', 'materialName', 'MaterialName'),
    materialColor: getStringField(slotRecord, '', 'materialColor', 'MaterialColor'),
  };
}

function normalizeMaterialStationInfo(machineInfo: unknown): MatlStationInfo | null {
  if (!isRecord(machineInfo)) {
    return null;
  }

  const detail = getObjectField(machineInfo, 'detail', 'Detail') ?? machineInfo;
  const station = getObjectField(detail, 'MatlStationInfo', 'matlStationInfo') ?? detail;
  const rawSlots = getArrayField(station, 'slotInfos', 'SlotInfos');
  const slots = rawSlots.map((slot, index) => normalizeSlotInfo(slot, index));
  const slotCount = getNumberField(station, slots.length, 'slotCnt', 'SlotCnt');
  const reportsMaterialStation =
    getBooleanField(detail, false, 'HasMatlStation', 'hasMatlStation') || slotCount > 0 || slots.length > 0;

  if (!reportsMaterialStation && rawSlots.length === 0) {
    return null;
  }

  return {
    currentLoadSlot: getNumberField(station, 0, 'currentLoadSlot', 'CurrentLoadSlot'),
    currentSlot: getNumberField(station, 0, 'currentSlot', 'CurrentSlot'),
    slotCnt: slotCount,
    slotInfos: slots,
    stateAction: getNumberField(station, 0, 'stateAction', 'StateAction'),
    stateStep: getNumberField(station, 0, 'stateStep', 'StateStep'),
  };
}

/**
 * Type guard to check if a job is an AD5X job with material data
 */
export function isAD5XJobInfo(value: unknown): value is AD5XJobInfo {
  if (!value || typeof value !== 'object') return false;

  const obj = value as Record<string, unknown>;
  return 'fileName' in obj && typeof obj.fileName === 'string' && ('toolDatas' in obj || '_type' in obj);
}

/**
 * Extract material station status from AD5X machine info
 * Handles validation and transformation in one place
 */
export function extractMaterialStationStatus(machineInfo: unknown): MaterialStationStatus | null {
  if (!isAD5XMachineInfo(machineInfo)) {
    return null;
  }

  const stationInfo = normalizeMaterialStationInfo(machineInfo);
  if (!stationInfo) {
    return null;
  }

  try {
    return transformMaterialStation(stationInfo);
  } catch (error) {
    console.error('Error extracting material station status:', error);
    return createEmptyMaterialStation();
  }
}
