export type AvailableShift = {
  id: string;
  role: string;
  client: string;
  site: string;
  startsAt: string;
  endsAt: string;
  rate: number;
  requirements: string[];
  availableSlots: number;
};

export function formatShiftTime(startsAt: string, endsAt: string): string;
export function parseRequirements(value: unknown): string[];
export function normalizeAvailableShift(row: unknown): AvailableShift | null;
export function shiftAccessibilityLabel(shift: AvailableShift): string;
