import { ViewHook } from 'phoenix_live_view';
import { markWelcomeSeen, welcomeSeen } from './storage';

// The welcome box on the map is rendered hidden and only shown to people who
// didn't close it before.
export default class WelcomeBox extends ViewHook {
  mounted() {
    if (welcomeSeen()) return;

    this.el.hidden = false;
    this.el.querySelectorAll('[data-welcome-close]').forEach((button) => {
      button.addEventListener('click', () => this.close());
    });

    // On phones the box covers the page, the focus goes into it. Not when the
    // details of a shared link are open, they are in front of the box.
    const fullScreen = window.matchMedia('(max-width: 50em)').matches;
    if (fullScreen && !document.getElementById('details-modal')) {
      this.el.querySelector<HTMLElement>('.map--welcome--start')?.focus();
    }
  }

  close() {
    markWelcomeSeen();
    this.el.hidden = true;
  }
}
