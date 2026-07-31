import { Controller } from '@hotwired/stimulus';
import flatpickr from 'flatpickr';
import type { Instance as FlatpickrInstance } from 'flatpickr/dist/types/instance';

// Derives checklist progress from the rendered items so the server does not
// have to supply a second, redundant count.
export class ChecklistController extends Controller {
  static targets = ['item', 'bar', 'label'];

  declare readonly itemTargets: HTMLElement[];
  declare readonly barTarget: HTMLProgressElement;
  declare readonly labelTarget: HTMLElement;
  declare readonly hasBarTarget: boolean;
  declare readonly hasLabelTarget: boolean;

  connect(): void {
    this.render();
  }

  itemTargetConnected(): void {
    this.render();
  }

  itemTargetDisconnected(): void {
    this.render();
  }

  private render(): void {
    const total = this.itemTargets.length;
    const done = this.itemTargets.filter((item) => item.classList.contains('completed')).length;
    if (this.hasBarTarget) {
      this.barTarget.max = Math.max(total, 1);
      this.barTarget.value = done;
    }
    if (this.hasLabelTarget) {
      this.labelTarget.textContent = total ? `${done} of ${total}` : 'No items';
    }
  }
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

  choose(): void {
    const file = this.inputTarget.files?.[0];
    this.nameTarget.textContent = file ? file.name : 'No file chosen';
    this.resetFeedback();
  }

  upload(event: SubmitEvent): void {
    const file = this.inputTarget.files?.[0];
    if (!file || !this.element.reportValidity()) {
      return;
    }

    event.preventDefault();
    if (file.size > MAX_ATTACHMENT_BYTES) {
      this.showError('Choose a file that is 10 MB or smaller.');
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
        this.barTarget.removeAttribute('value');
        this.percentTarget.textContent = '';
        return;
      }

      const percent = Math.round((progressEvent.loaded / progressEvent.total) * 100);
      this.barTarget.value = percent;
      this.percentTarget.textContent = `${percent}%`;
    });
    request.upload.addEventListener('load', () => {
      this.barTarget.value = 100;
      this.statusTarget.textContent = 'Saving…';
      this.percentTarget.textContent = '100%';
    });
    request.addEventListener('load', () => {
      if (request.status >= 200 && request.status < 400) {
        window.location.assign(request.responseURL || this.element.action);
        return;
      }

      this.finishWithError(
        request.status === 413
          ? 'Choose a file that is 10 MB or smaller.'
          : 'The upload failed. Refresh the page and try again.',
      );
    });
    request.addEventListener('error', () => {
      this.finishWithError('The network connection stopped the upload. Try again.');
    });

    this.element.setAttribute('aria-busy', 'true');
    this.buttonTarget.disabled = true;
    this.panelTarget.hidden = false;
    this.errorTarget.hidden = true;
    this.barTarget.value = 0;
    this.statusTarget.textContent = 'Uploading…';
    this.percentTarget.textContent = '0%';
    request.send(formData);
  }

  private resetFeedback(): void {
    this.panelTarget.hidden = true;
    this.errorTarget.hidden = true;
  }

  private showError(message: string): void {
    this.errorTarget.textContent = message;
    this.errorTarget.hidden = false;
  }

  private finishWithError(message: string): void {
    this.element.removeAttribute('aria-busy');
    this.buttonTarget.disabled = false;
    this.statusTarget.textContent = 'Upload stopped';
    this.showError(message);
  }
}

export class MenuController extends Controller {
  static targets = ['trigger', 'panel', 'input', 'value', 'option'];

  declare readonly triggerTarget: HTMLButtonElement;
  declare readonly panelTarget: HTMLElement;
  declare readonly inputTarget: HTMLInputElement;
  declare readonly valueTarget: HTMLElement;
  declare readonly hasValueTarget: boolean;
  declare readonly optionTargets: HTMLElement[];

  connect(): void {
    this.element.addEventListener('keydown', this.handleKeydown);
  }

  disconnect(): void {
    this.element.removeEventListener('keydown', this.handleKeydown);
  }

  toggle(event: Event): void {
    event.stopPropagation();
    this.panelTarget.hidden ? this.open() : this.close();
  }

  choose(event: Event): void {
    const option = event.currentTarget as HTMLElement;
    const value = option.dataset.value ?? '';
    const label = option.dataset.label ?? option.textContent?.trim() ?? '';
    this.inputTarget.value = value;
    if (this.hasValueTarget) {
      this.valueTarget.textContent = label;
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
    this.panelTarget.hidden = true;
    this.triggerTarget.setAttribute('aria-expanded', 'false');
  }

  private open(): void {
    this.panelTarget.hidden = false;
    this.triggerTarget.setAttribute('aria-expanded', 'true');
    this.optionTargets.find((option) => option.getAttribute('aria-selected') === 'true')?.focus();
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

  open(): void {
    this.panelTarget.hidden = false;
    document.body.classList.add('no-scroll');
    requestAnimationFrame(() => {
      this.panelTarget.dataset.open = 'true';
      (this.hasInitialTarget ? this.initialTarget : this.panelTarget).focus();
    });
  }

  close(): void {
    delete this.panelTarget.dataset.open;
    document.body.classList.remove('no-scroll');
    setTimeout(() => {
      this.panelTarget.hidden = true;
    }, 120);
  }

  backdrop(event: Event): void {
    if (event.target === this.panelTarget) {
      this.close();
    }
  }
}

export class DatePickerController extends Controller {
  static targets = ['input'];

  declare readonly inputTarget: HTMLInputElement;
  private picker?: FlatpickrInstance;

  connect(): void {
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
  }

  disconnect(): void {
    this.picker?.destroy();
  }

  clear(): void {
    this.picker?.clear();
  }
}
