import 'phoenix_html';
import { Socket } from 'phoenix';
import { LiveSocket } from 'phoenix_live_view';
import topbar from 'topbar';
import InteractiveMap from './interactiveMap';
import WelcomeBox from './welcomeBox';
import SearchCombobox from './searchCombobox';
import ListPopup from './listPopup';
import ShareButton from './shareButton';
import DetailsMap from './detailsMap';
import { setupNavigation } from './navigation';
import { storedListFilters, storedMapPosition } from './storage';
import SubscriptionMap, { setupSubscriptionMaps } from './subscriptionMap';

// Another entry in an open details dialog starts at the top, not at the
// scroll position of the entry before
type DetailsScrollTopHook = { el: HTMLElement, content?: HTMLElement | null, onFocus?: () => void };
const DetailsScrollTop = {
  mounted(this: DetailsScrollTopHook) {
    this.content = this.el.closest<HTMLElement>('.phx-modal-content');
    if (!this.content) return;
    this.content.scrollTop = 0;

    // Wide screens: only the text scrolls (map.scss). When the dialog focuses its
    // content, the text gets the focus instead, so the arrow keys scroll it.
    const text = this.el.querySelector<HTMLElement>('.details--text');
    this.onFocus = () => {
      if (!text || getComputedStyle(text).overflowY !== 'auto') return;
      text.tabIndex = -1;
      text.focus({ preventScroll: true });
    };
    this.content.addEventListener('focus', this.onFocus);
    if (document.activeElement === this.content) this.onFocus();
  },
  destroyed(this: DetailsScrollTopHook) {
    if (this.content && this.onFocus) this.content.removeEventListener('focus', this.onFocus);
  },
};

const csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute('content');
const liveSocket = new LiveSocket('/live', Socket, {
  hooks: {
    InteractiveMap, WelcomeBox, SearchCombobox, ListPopup, ShareButton, DetailsMap, DetailsScrollTop, SubscriptionMap,
  },
  // evaluated on every (re)connect, the map opens at the last position with the
  // filters of the last visit
  params: () => ({
    _csrf_token: csrfToken,
    map_position: storedMapPosition(),
    list_filters: storedListFilters(),
  }),
});

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: '#29d' }, shadowColor: 'rgba(0, 0, 0, .3)' });
window.addEventListener('phx:page-loading-start', () => topbar.show(300));
window.addEventListener('phx:page-loading-stop', () => topbar.hide());

liveSocket.connect();
setupNavigation();
setupSubscriptionMaps();

declare global {
  interface Window {
    liveSocket: LiveSocket;
  }
}
window.liveSocket = liveSocket;
