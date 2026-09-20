import { ViewHook } from 'phoenix_live_view';

export const FLY_TO_EVENT = 'hierbautberlin:fly-to';
export type FlyToDetail = { lat: number, lng: number };

// pushEvent rejects when the LiveView is not connected and an unhandled
// rejection is reported as an error. Without a connection there are no search
// results either, so there is nothing else to do about it.
const ignoreDisconnected = () => {};

// Street search as combobox (https://www.w3.org/WAI/ARIA/apg/patterns/combobox/).
// The focus stays in the input, the highlighted option is announced with
// aria-activedescendant. The results are rendered by the LiveView, the
// highlight lives here and is applied again after every update.
export default class SearchCombobox extends ViewHook {
  input!: HTMLInputElement;

  activeIndex = -1;

  query?: string;

  mounted() {
    this.input = this.el.querySelector<HTMLInputElement>('[role="combobox"]')!;
    this.query = this.listbox().dataset.query;

    this.input.addEventListener('keydown', (event) => this.onKeydown(event));
    this.input.addEventListener('blur', () => {
      if (this.isOpen()) this.close();
    });

    const results = this.resultsContainer();
    // keeps the focus in the input when clicking an option or the scrollbar
    results.addEventListener('mousedown', (event) => event.preventDefault());
    results.addEventListener('click', (event) => {
      const option = (event.target as HTMLElement).closest<HTMLElement>('[role="option"]');
      if (option) this.select(option);
    });
    results.addEventListener('mousemove', (event) => {
      const option = (event.target as HTMLElement).closest<HTMLElement>('[role="option"]');
      const index = option ? this.options().indexOf(option) : -1;
      if (index >= 0 && index !== this.activeIndex) this.highlight(index, false);
    });
  }

  updated() {
    const { query } = this.listbox().dataset;
    // new results, nothing is highlighted
    if (query !== this.query) {
      this.query = query;
      this.activeIndex = -1;
    }
    this.highlight(Math.min(this.activeIndex, this.options().length - 1), false);
  }

  onKeydown(event: KeyboardEvent) {
    const options = this.options();

    switch (event.key) {
      case 'ArrowDown':
        if (options.length === 0) return;
        event.preventDefault();
        if (!this.isOpen()) this.pushEvent('show-results', {}).catch(ignoreDisconnected);
        this.highlight(Math.min(this.activeIndex + 1, options.length - 1), true);
        break;
      case 'ArrowUp':
        if (!this.isOpen()) return;
        event.preventDefault();
        // from the first option back into the input
        this.highlight(this.activeIndex - 1, true);
        break;
      case 'Enter':
        if (!this.isOpen() || options.length === 0) return;
        event.preventDefault();
        this.select(options[Math.max(this.activeIndex, 0)]);
        break;
      case 'Escape':
        if (!this.isOpen()) return;
        event.preventDefault();
        this.close();
        break;
      default:
    }
  }

  highlight(index: number, scroll: boolean) {
    this.activeIndex = index;

    this.options().forEach((option, optionIndex) => {
      const active = optionIndex === index;
      option.setAttribute('aria-selected', String(active));
      option.classList.toggle('map--search-result--active', active);
      if (active) {
        this.input.setAttribute('aria-activedescendant', option.id);
        if (scroll) option.scrollIntoView({ block: 'nearest' });
      }
    });

    if (index < 0) this.input.removeAttribute('aria-activedescendant');
  }

  select(option: HTMLElement) {
    const detail: FlyToDetail = {
      lat: parseFloat(option.dataset.lat || ''),
      lng: parseFloat(option.dataset.lng || ''),
    };
    window.dispatchEvent(new CustomEvent<FlyToDetail>(FLY_TO_EVENT, { detail }));

    const name = option.dataset.name || '';
    this.input.value = name;
    this.highlight(-1, false);
    this.pushEvent('select-search-result', { name }).catch(ignoreDisconnected);
  }

  close() {
    this.highlight(-1, false);
    this.pushEvent('hide-results', {}).catch(ignoreDisconnected);
  }

  isOpen() {
    return !this.resultsContainer().hidden;
  }

  resultsContainer() {
    return this.el.querySelector<HTMLElement>('.map--search-results')!;
  }

  listbox() {
    return this.el.querySelector<HTMLElement>('[role="listbox"]')!;
  }

  options() {
    return Array.from(this.el.querySelectorAll<HTMLElement>('[role="option"]'));
  }
}
