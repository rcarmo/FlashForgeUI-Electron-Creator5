/**
 * @fileoverview Type declarations for the vendored slicer metadata parser.
 */

export interface FilamentInfo {
  readonly type?: string;
  readonly color?: string;
  readonly usedMM?: string;
  readonly usedM?: string;
  readonly usedG?: string;
}

export interface SliceWarning {
  readonly level: number;
  readonly message?: string;
  readonly msg: string;
}

export interface FileMetadata {
  readonly fileName?: string;
  readonly filePath?: string;
  readonly fileSize?: number;
  readonly printerModel?: string;
  readonly filamentType?: string;
  readonly filamentUsedMM?: number;
  readonly filamentUsedG?: number;
  readonly filaments?: readonly FilamentInfo[];
  readonly thumbnail?: string;
  readonly layerHeight?: number;
  readonly infill?: number;
  readonly layers?: number;
}

export interface SlicerInfo {
  readonly slicerName?: string;
  readonly slicerVersion?: string;
  readonly sliceDate?: string;
  readonly sliceTime?: string;
  readonly printEta?: string;
}

export interface ThreeMfMetadata {
  readonly printerModelId?: string;
  readonly supportUsed?: boolean;
  readonly filaments?: readonly FilamentInfo[];
  readonly plateImage?: string;
  readonly layerHeight?: number;
  readonly infill?: number;
  readonly layerCount?: number;
  readonly firstLayerTime?: number;
  readonly warnings?: readonly SliceWarning[];
}

export interface ParseResult {
  readonly file?: FileMetadata;
  readonly slicer?: SlicerInfo;
  readonly threeMf?: ThreeMfMetadata;
}

export function parseSlicerFile(filePath: string): Promise<ParseResult>;

export const GCodeParser: { parse(filePath: string): ParseResult };
export const FlashPrintParser: { parse(filePath: string): ParseResult };
export const OrcaFlashForgeParser: { parse(filePath: string): ParseResult };
export const OrcaSlicerParser: { parse(filePath: string): ParseResult };
export const GXParser: { parse(filePath: string): ParseResult };
export const ThreeMfParser: { parse(filePath: string): ParseResult };
