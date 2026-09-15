import { ViewHook } from 'phoenix_live_view';

declare global {
  interface Window {
    plausible?: (event: string, options?: object) => void;
  }
}

const copyWithTextarea = (text: string) => {
  const textarea = document.createElement('textarea');
  textarea.value = text;
  textarea.setAttribute('readonly', '');
  textarea.style.position = 'fixed';
  textarea.style.opacity = '0';
  document.body.appendChild(textarea);
  textarea.select();
  const copied = document.execCommand('copy');
  textarea.remove();
  return copied;
};

const copyToClipboard = async (text: string) => {
  try {
    await navigator.clipboard.writeText(text);
    return true;
  } catch {
    // no clipboard access (e.g. no https or no permission)
    return copyWithTextarea(text);
  }
};

// Shares the link to an entry with the Web Share API (phones, Safari) and
// copies it to the clipboard where that isn't available.
export default class ShareButton extends ViewHook {
  statusTimeout?: number;

  mounted() {
    this.el.querySelector('button')?.addEventListener('click', () => this.share());
  }

  destroyed() {
    window.clearTimeout(this.statusTimeout);
  }

  async share() {
    const { url = '', title = '' } = this.el.dataset;
    window.plausible?.('Teilen');

    if (navigator.share) {
      try {
        await navigator.share({ title, url });
        return;
      } catch (error) {
        // closing the share dialog is no error, everything else copies the link
        if ((error as DOMException).name === 'AbortError') return;
      }
    }

    if (await copyToClipboard(url)) {
      this.showStatus('Link in die Zwischenablage kopiert');
    } else {
      this.showStatus(`Link: ${url}`);
    }
  }

  showStatus(message: string) {
    const status = this.el.querySelector<HTMLElement>('[role="status"]');
    if (!status) return;

    status.textContent = message;
    window.clearTimeout(this.statusTimeout);
    this.statusTimeout = window.setTimeout(() => { status.textContent = ''; }, 4000);
  }
}
