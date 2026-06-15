/**
 * @fileoverview Tests for AD5X material station extraction helpers.
 *
 * Verifies that IFS slot extraction accepts both ff-api transformed machine info
 * and raw FlashForge detail payload variants used by Creator 5/AD5X firmware.
 */

import { extractMaterialStationStatus } from '../ad5x/ad5x-utils.js';

describe('AD5X material station extraction', () => {
  it('extracts slots from transformed ff-api machine info', () => {
    const status = extractMaterialStationStatus({
      HasMatlStation: true,
      MatlStationInfo: {
        currentLoadSlot: 0,
        currentSlot: 2,
        slotCnt: 4,
        slotInfos: [
          {
            slotId: 1,
            hasFilament: true,
            materialName: 'PLA',
            materialColor: '#ff0000',
          },
          {
            slotId: 2,
            hasFilament: true,
            materialName: 'PETG',
            materialColor: '#00ff00',
          },
        ],
        stateAction: 0,
        stateStep: 0,
      },
    });

    expect(status).toMatchObject({
      connected: true,
      activeSlot: 2,
      overallStatus: 'ready',
      slots: [
        {
          slotId: 1,
          isEmpty: false,
          materialType: 'PLA',
          materialColor: '#ff0000',
        },
        {
          slotId: 2,
          isEmpty: false,
          materialType: 'PETG',
          materialColor: '#00ff00',
        },
      ],
    });
  });

  it('extracts slots from raw lowercase detail payloads with numeric station flags', () => {
    const status = extractMaterialStationStatus({
      detail: {
        hasMatlStation: 1,
        matlStationInfo: {
          currentSlot: '3',
          slotCnt: '4',
          slotInfos: [
            {
              slotId: '3',
              hasFilament: 1,
              materialName: 'PLA',
              materialColor: '3366ff',
            },
          ],
          stateAction: '1',
          stateStep: 0,
        },
      },
    });

    expect(status).toMatchObject({
      connected: true,
      activeSlot: 3,
      overallStatus: 'warming',
      slots: [
        {
          slotId: 3,
          isEmpty: false,
          materialType: 'PLA',
          materialColor: '3366ff',
        },
      ],
    });
  });

  it('extracts slots from raw capitalized detail payloads', () => {
    const status = extractMaterialStationStatus({
      Detail: {
        HasMatlStation: true,
        MatlStationInfo: {
          CurrentSlot: 4,
          SlotCnt: 4,
          SlotInfos: [
            {
              SlotId: 4,
              HasFilament: true,
              MaterialName: 'ABS',
              MaterialColor: '#ffffff',
            },
          ],
          StateAction: 0,
          StateStep: 0,
        },
      },
    });

    expect(status?.slots).toEqual([
      {
        slotId: 4,
        isEmpty: false,
        materialType: 'ABS',
        materialColor: '#ffffff',
      },
    ]);
  });

  it('returns an empty connected station when only the material-station flag is present', () => {
    const status = extractMaterialStationStatus({
      hasMatlStation: true,
      matlStationInfo: {
        slotCnt: 4,
      },
    });

    expect(status).toMatchObject({
      connected: true,
      activeSlot: 0,
      slots: [],
      errorMessage: null,
    });
  });
});
