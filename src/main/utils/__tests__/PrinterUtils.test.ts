/**
 * @fileoverview Tests for FlashForge printer model and family detection helpers.
 *
 * Verifies that firmware-reported TypeName values map to the correct backend
 * model, client family, and pairing-code behavior used during connection setup.
 */

import {
  detectPrinterFamily,
  detectPrinterModelType,
  shouldPromptForCheckCode,
} from '../PrinterUtils.js';

describe('PrinterUtils model detection', () => {
  it.each(['FlashForge Creator 5', 'Creator 5', 'FlashForge Creator5'])(
    'treats %s as an AD5X-class printer',
    (typeName) => {
      expect(detectPrinterModelType(typeName)).toBe('ad5x');

      const family = detectPrinterFamily(typeName);
      expect(family).toEqual({
        is5MFamily: true,
        requiresCheckCode: true,
        familyName: 'AD5X',
      });
      expect(shouldPromptForCheckCode(family.is5MFamily)).toBe(true);
    }
  );

  it('keeps existing AD5X and Adventurer 5M classification intact', () => {
    expect(detectPrinterModelType('AD5X')).toBe('ad5x');
    expect(detectPrinterModelType('FlashForge Adventurer 5M Pro')).toBe('adventurer-5m-pro');
    expect(detectPrinterModelType('FlashForge Adventurer 5M')).toBe('adventurer-5m');
  });

  it('does not classify unrelated Creator models as AD5X-class printers', () => {
    expect(detectPrinterModelType('FlashForge Creator Pro')).toBe('generic-legacy');
    expect(detectPrinterFamily('FlashForge Creator Pro')).toMatchObject({
      is5MFamily: false,
      requiresCheckCode: false,
    });
  });
});
