declare global {
  namespace App {}

  namespace svelteHTML {
    interface IntrinsicElements {
      'hex-color-picker': {
        class?: string;
        color?: string;
      };
    }
  }
}

export {};
