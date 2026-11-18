// DOM references and section scroll mapping shared between React and the 3D director.
export interface UiRefs {
  veil: HTMLElement;
  nav: HTMLElement;
  hero: HTMLElement;
  scrollCue: HTMLElement;
  gaze: HTMLElement;
  tamper: HTMLElement;
  phone: HTMLElement;
  macos: HTMLElement;
  final: HTMLElement;
  labels: HTMLElement;
}

export const SECTIONS = {
  overview: 0,
  gaze: 0.22,
  tamper: 0.46,
  phone: 0.68,
  macos: 0.86,
} as const;

export type SectionName = keyof typeof SECTIONS;

export const sectionAt = (p: number): SectionName | null =>
  p < 0.12 ? "overview" : p < 0.34 ? "gaze" : p < 0.57 ? "tamper" : p < 0.77 ? "phone" : p < 0.94 ? "macos" : null;

export const isSection = (name: string): name is SectionName => Object.hasOwn(SECTIONS, name);
