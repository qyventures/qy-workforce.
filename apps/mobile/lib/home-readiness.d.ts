export type HomeReadinessPresentation = {
  label: string;
  detail: string;
  ready: boolean;
};

export function homeReadinessPresentation(value: Record<string, unknown> | null | undefined): HomeReadinessPresentation;
