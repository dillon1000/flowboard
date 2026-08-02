import { Controller } from '@hotwired/stimulus';

interface NDEFWriter {
  write(message: { records: Array<{ recordType: 'url'; data: string }> }): Promise<void>;
}

interface NDEFWriterConstructor {
  new (): NDEFWriter;
}

type NFCWindow = Window & { NDEFReader?: NDEFWriterConstructor };

/** Switches the scanner-input defaults or fixed update fields when action type changes. */
export class TapActionFormController extends Controller<HTMLFormElement> {
  static targets = ['kind', 'createFields', 'updateFields'];

  declare readonly kindTarget: HTMLInputElement;
  declare readonly createFieldsTarget: HTMLElement;
  declare readonly updateFieldsTarget: HTMLElement;

  connect(): void {
    this.update();
  }

  update(): void {
    const isUpdate = this.kindTarget.value === 'update_task';
    this.setGroupEnabled(this.createFieldsTarget, !isUpdate);
    this.setGroupEnabled(this.updateFieldsTarget, isUpdate);
  }

  private setGroupEnabled(group: HTMLElement, enabled: boolean): void {
    group.hidden = !enabled;
    group.querySelectorAll<HTMLInputElement | HTMLTextAreaElement>('[name]').forEach((field) => {
      field.disabled = !enabled;
    });
  }
}

/** Copies the one-time capability URL or writes it as an NFC URL record. */
export class TapProvisionController extends Controller {
  static targets = ['url', 'status', 'write'];

  declare readonly urlTarget: HTMLElement;
  declare readonly statusTarget: HTMLElement;
  declare readonly writeTarget: HTMLButtonElement;

  connect(): void {
    this.writeTarget.hidden = !(window as NFCWindow).NDEFReader;
  }

  async copy(): Promise<void> {
    try {
      await navigator.clipboard.writeText(this.url());
      this.statusTarget.textContent = 'Link copied.';
    } catch {
      this.statusTarget.textContent = 'Copy failed. Select the link and copy it manually.';
    }
  }

  async write(): Promise<void> {
    const Writer = (window as NFCWindow).NDEFReader;
    if (!Writer) {
      return;
    }

    this.writeTarget.disabled = true;
    this.statusTarget.textContent = 'Hold the NFC tag near this phone…';
    try {
      await new Writer().write({ records: [{ recordType: 'url', data: this.url() }] });
      this.statusTarget.textContent = 'Tag written.';
    } catch {
      this.statusTarget.textContent = 'The tag was not written. Try again or copy the link.';
    } finally {
      this.writeTarget.disabled = false;
    }
  }

  private url(): string {
    return this.urlTarget.textContent?.trim() ?? '';
  }
}
