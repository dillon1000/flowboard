export const tourState = $state({ active: false, step: 0 });

export function startTour(): void {
  tourState.step = 0;
  tourState.active = true;
}

export function endTour(): void {
  tourState.active = false;
}
