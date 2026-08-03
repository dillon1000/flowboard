import { Controller } from '@hotwired/stimulus';
import flatpickr from 'flatpickr';
import type { Instance as FlatpickrInstance } from 'flatpickr/dist/types/instance';
import { autorun, type IReactionDisposer } from 'mobx';
import 'vanilla-colorful';
import type { HexColorPicker } from 'vanilla-colorful';
import { appStore, type UploadState } from '../stores/app_store';

let nextOverlayID = 0;

// Runtime IDs let menus and dialogs share one active-overlay state without
// requiring stable IDs in every server-rendered template.
function createOverlayID(type: 'dialog' | 'menu'): string {
  nextOverlayID += 1;
  return `${type}-${nextOverlayID}`;
}

// MAX_ATTACHMENT_BYTES matches the server limit. Changing either value changes
// which files the browser accepts before it starts the network request.
const MAX_ATTACHMENT_BYTES = 10_000_000;

// Shows the selected file and reports browser-to-server upload progress. The
// saving state covers the later server-to-bucket write, which has no browser
// progress events.
export class FileFieldController extends Controller<HTMLFormElement> {
  static targets = ['input', 'name', 'button', 'panel', 'bar', 'status', 'percent', 'error'];

  declare readonly inputTarget: HTMLInputElement;
  declare readonly nameTarget: HTMLElement;
  declare readonly buttonTarget: HTMLButtonElement;
  declare readonly panelTarget: HTMLElement;
  declare readonly barTarget: HTMLProgressElement;
  declare readonly statusTarget: HTMLElement;
  declare readonly percentTarget: HTMLElement;
  declare readonly errorTarget: HTMLElement;
  private stopObserving?: IReactionDisposer;

  connect(): void {
    appStore.resetUpload();
    this.stopObserving = autorun(() => this.render(appStore.upload));
  }

  disconnect(): void {
    this.stopObserving?.();
  }

  choose(): void {
    const file = this.inputTarget.files?.[0];
    appStore.selectUploadFile(file?.name ?? null);
  }

  upload(event: SubmitEvent): void {
    const file = this.inputTarget.files?.[0];
    if (!file || !this.element.reportValidity()) {
      return;
    }

    event.preventDefault();
    if (file.size > MAX_ATTACHMENT_BYTES) {
      appStore.rejectUpload('Choose a file that is 10 MB or smaller.');
      return;
    }

    const request = new XMLHttpRequest();
    const formData = new FormData(this.element);
    request.open(this.element.method || 'post', this.element.action);
    request.setRequestHeader('Accept', 'text/html');
    request.setRequestHeader(
      'X-CSRF-TOKEN',
      document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content ?? '',
    );
    request.upload.addEventListener('progress', (progressEvent) => {
      if (!progressEvent.lengthComputable) {
        appStore.updateUploadProgress(null);
        return;
      }

      const percent = Math.round((progressEvent.loaded / progressEvent.total) * 100);
      appStore.updateUploadProgress(percent);
    });
    request.upload.addEventListener('load', () => {
      appStore.saveUpload();
    });
    request.addEventListener('load', () => {
      if (request.status >= 200 && request.status < 400) {
        window.location.assign(request.responseURL || this.element.action);
        return;
      }

      appStore.failUpload(
        request.status === 413
          ? 'Choose a file that is 10 MB or smaller.'
          : 'The upload failed. Refresh the page and try again.',
      );
    });
    request.addEventListener('error', () => {
      appStore.failUpload('The network connection stopped the upload. Try again.');
    });

    appStore.startUpload();
    request.send(formData);
  }

  private render(state: UploadState): void {
    const busy = state.phase === 'uploading' || state.phase === 'saving';
    this.nameTarget.textContent = state.fileName ?? 'No file chosen';
    this.buttonTarget.disabled = busy;
    this.panelTarget.hidden = !state.progressVisible;
    this.errorTarget.hidden = !state.error;
    this.errorTarget.textContent = state.error ?? '';
    if (busy) {
      this.element.setAttribute('aria-busy', 'true');
    } else {
      this.element.removeAttribute('aria-busy');
    }
    if (state.percent === null) {
      this.barTarget.removeAttribute('value');
      this.percentTarget.textContent = '';
    } else {
      this.barTarget.value = state.percent;
      this.percentTarget.textContent = `${state.percent}%`;
    }
    this.statusTarget.textContent = state.phase === 'saving'
      ? 'Saving…'
      : state.phase === 'error'
        ? 'Upload stopped'
        : state.phase === 'uploading'
          ? 'Uploading…'
          : '';
  }
}

export class MenuController extends Controller {
  static targets = ['trigger', 'panel', 'input', 'value', 'option', 'swatch'];

  declare readonly triggerTarget: HTMLButtonElement;
  declare readonly panelTarget: HTMLElement;
  declare readonly inputTarget: HTMLInputElement;
  declare readonly valueTarget: HTMLElement;
  declare readonly hasValueTarget: boolean;
  declare readonly optionTargets: HTMLElement[];
  declare readonly swatchTarget: HTMLElement;
  declare readonly hasSwatchTarget: boolean;
  private readonly overlayID = createOverlayID('menu');
  private stopObserving?: IReactionDisposer;

  connect(): void {
    this.element.addEventListener('keydown', this.handleKeydown);
    this.stopObserving = autorun(() => (
      this.renderOpen(appStore.activeOverlayIDs.menu === this.overlayID)
    ));
  }

  disconnect(): void {
    this.element.removeEventListener('keydown', this.handleKeydown);
    this.stopObserving?.();
    appStore.closeOverlay('menu', this.overlayID);
  }

  toggle(event: Event): void {
    event.stopPropagation();
    appStore.activeOverlayIDs.menu === this.overlayID ? this.close() : this.open();
  }

  choose(event: Event): void {
    const option = event.currentTarget as HTMLElement;
    const value = option.dataset.value ?? '';
    const label = option.dataset.label ?? option.textContent?.trim() ?? '';
    this.inputTarget.value = value;
    if (this.hasValueTarget) {
      this.valueTarget.textContent = label;
    }
    // Menus with a visual preview expose a swatch target whose color token
    // follows the submitted input value.
    if (this.hasSwatchTarget) {
      this.swatchTarget.dataset.color = value;
    }
    this.optionTargets.forEach((item) => {
      item.setAttribute('aria-selected', String(item === option));
    });
    this.inputTarget.dispatchEvent(new Event('change', { bubbles: true }));
    this.close();
    // Status popovers opt in to immediate submission. Other menus keep their
    // current behavior and only update the surrounding form field.
    if (this.element instanceof HTMLFormElement && this.element.dataset.submitOnChoose === 'true') {
      this.element.requestSubmit();
    }
  }

  outside(event: Event): void {
    if (!this.element.contains(event.target as Node)) {
      this.close();
    }
  }

  close(): void {
    appStore.closeOverlay('menu', this.overlayID);
  }

  private open(): void {
    appStore.openOverlay('menu', this.overlayID);
  }

  private renderOpen(open: boolean): void {
    this.panelTarget.hidden = !open;
    this.triggerTarget.setAttribute('aria-expanded', String(open));
    if (open) {
      this.optionTargets.find((option) => option.getAttribute('aria-selected') === 'true')?.focus();
    }
  }

  private handleKeydown = (event: Event): void => {
    const keyboardEvent = event as KeyboardEvent;
    if (keyboardEvent.key !== 'ArrowDown' && keyboardEvent.key !== 'ArrowUp') {
      return;
    }
    keyboardEvent.preventDefault();
    if (this.panelTarget.hidden) {
      this.open();
      return;
    }
    const currentIndex = this.optionTargets.indexOf(document.activeElement as HTMLElement);
    const delta = keyboardEvent.key === 'ArrowDown' ? 1 : -1;
    const nextIndex = (currentIndex + delta + this.optionTargets.length) % this.optionTargets.length;
    this.optionTargets[nextIndex]?.focus();
  };
}

const PRESET_COLOR_HEX: Record<string, string> = {
  gray: '#7d7d7d',
  blue: '#0068d7',
  purple: '#7c3aed',
  green: '#2f8f46',
  amber: '#e6a500',
  orange: '#f27b0a',
  red: '#dc3636',
};
const CUSTOM_COLOR_PATTERN = /^#[0-9a-f]{6}$/i;

/** Keeps preset, spectrum, hex, preview, and submitted workflow colors in sync. */
export class ColorPickerController extends Controller {
  static targets = ['input', 'picker', 'hex', 'swatch', 'label', 'preset'];

  declare readonly inputTarget: HTMLInputElement;
  declare readonly pickerTarget: HexColorPicker;
  declare readonly hexTarget: HTMLInputElement;
  declare readonly swatchTarget: HTMLElement;
  declare readonly labelTarget: HTMLElement;
  declare readonly presetTargets: HTMLButtonElement[];

  connect(): void {
    const presetHex = PRESET_COLOR_HEX[this.inputTarget.value];
    if (presetHex) {
      this.syncPreset(this.inputTarget.value, presetHex);
      return;
    }
    this.syncCustom(this.inputTarget.value);
  }

  preset(event: Event): void {
    const token = (event.currentTarget as HTMLElement).dataset.value ?? '';
    const hex = PRESET_COLOR_HEX[token];
    if (hex) {
      this.syncPreset(token, hex);
    }
  }

  custom(event: Event): void {
    const colorEvent = event as CustomEvent<{ value: string }>;
    this.syncCustom(colorEvent.detail.value);
  }

  type(event: Event): void {
    const value = `#${(event.currentTarget as HTMLInputElement).value}`;
    if (CUSTOM_COLOR_PATTERN.test(value)) {
      this.syncCustom(value);
    }
  }

  private syncPreset(token: string, hex: string): void {
    this.pickerTarget.color = hex;
    this.hexTarget.value = hex.slice(1).toUpperCase();
    this.hexTarget.removeAttribute('aria-invalid');
    this.swatchTarget.dataset.color = token;
    this.swatchTarget.style.removeProperty('--color-picker-value');
  }

  private syncCustom(value: string): void {
    const normalized = value.toLowerCase();
    if (!CUSTOM_COLOR_PATTERN.test(normalized)) {
      this.hexTarget.setAttribute('aria-invalid', 'true');
      return;
    }

    this.inputTarget.value = normalized;
    this.pickerTarget.color = normalized;
    this.hexTarget.value = normalized.slice(1).toUpperCase();
    this.hexTarget.removeAttribute('aria-invalid');
    this.swatchTarget.dataset.color = 'custom';
    this.swatchTarget.style.setProperty('--color-picker-value', normalized);
    this.labelTarget.textContent = normalized.toUpperCase();
    this.presetTargets.forEach((preset) => preset.setAttribute('aria-selected', 'false'));
    this.inputTarget.dispatchEvent(new Event('change', { bubbles: true }));
  }
}

/** Shows the option-name input only for fields whose values come from a fixed list. */
export class PropertyDefinitionController extends Controller {
  static targets = ['type', 'options'];

  declare readonly typeTarget: HTMLInputElement;
  declare readonly optionsTarget: HTMLInputElement;

  connect(): void {
    this.update();
  }

  update(): void {
    const usesOptions = ['select', 'multi_select'].includes(this.typeTarget.value);
    this.optionsTarget.hidden = !usesOptions;
    this.optionsTarget.required = usesOptions;
  }
}

export class DialogController extends Controller {
  static targets = ['panel', 'initial'];

  declare readonly panelTarget: HTMLElement;
  declare readonly hasInitialTarget: boolean;
  declare readonly initialTarget: HTMLElement;
  private readonly overlayID = createOverlayID('dialog');
  private stopObserving?: IReactionDisposer;

  connect(): void {
    this.stopObserving = autorun(() => (
      this.renderOpen(appStore.activeOverlayIDs.dialog === this.overlayID)
    ));
  }

  disconnect(): void {
    this.stopObserving?.();
    appStore.closeOverlay('dialog', this.overlayID);
  }

  open(): void {
    appStore.openOverlay('dialog', this.overlayID);
  }

  close(): void {
    appStore.closeOverlay('dialog', this.overlayID);
  }

  backdrop(event: Event): void {
    if (event.target === this.panelTarget) {
      this.close();
    }
  }

  private renderOpen(open: boolean): void {
    const dialogActive = Boolean(appStore.activeOverlayIDs.dialog);
    document.body.classList.toggle('no-scroll', dialogActive);
    if (open) {
      this.panelTarget.hidden = false;
      requestAnimationFrame(() => {
        if (appStore.activeOverlayIDs.dialog === this.overlayID) {
          this.panelTarget.dataset.open = 'true';
          (this.hasInitialTarget ? this.initialTarget : this.panelTarget).focus();
        }
      });
      return;
    }

    delete this.panelTarget.dataset.open;
    setTimeout(() => {
      if (appStore.activeOverlayIDs.dialog !== this.overlayID) {
        this.panelTarget.hidden = true;
      }
    }, 120);
  }
}

export class DatePickerController extends Controller {
  static targets = ['input'];

  declare readonly inputTarget: HTMLInputElement;
  private picker?: FlatpickrInstance;

  connect(): void {
    const label = this.inputTarget.labels?.[0]?.textContent?.trim();
    this.picker = flatpickr(this.inputTarget, {
      allowInput: false,
      altInput: true,
      altFormat: 'M j, Y',
      dateFormat: 'Y-m-d',
      disableMobile: true,
      monthSelectorType: 'static',
      nextArrow: '<span aria-hidden="true">→</span>',
      prevArrow: '<span aria-hidden="true">←</span>',
    });

    // Flatpickr hides the labeled input and creates a visible replacement. Copy
    // the label so assistive technology can still identify the date control.
    if (label && this.picker.altInput) {
      this.picker.altInput.setAttribute('aria-label', label);
    }
  }

  disconnect(): void {
    this.picker?.destroy();
  }

  clear(): void {
    this.picker?.clear();
  }
}
