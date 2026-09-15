import { ViewHook } from 'phoenix_live_view';

// Escape inside a popup of the list toolbar closes it and moves the focus back
// to its button. The close command is rendered by the LiveView (data-close).
export default class ListPopup extends ViewHook {
  mounted() {
    this.el.addEventListener('keydown', (event) => {
      if (event.key !== 'Escape') return;

      const popup = this.el.querySelector<HTMLElement>('.map--list-popup');
      if (!popup || getComputedStyle(popup).display === 'none') return;

      event.preventDefault();
      event.stopPropagation();
      this.js().exec(this.el.dataset.close || '[]');
    });
  }
}
