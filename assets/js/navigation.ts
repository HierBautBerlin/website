import { storedMapPosition } from './storage';

// The menu on phones: a button that opens the menu panel. The page behind it
// is inert while it is open, Escape closes it.

const DEFAULT_POSITION = { lat: 52.5166309, lng: 13.3781537 };

// The RSS link in the menu is the feed of the current map position
export const updateFeedLink = (position: { lat: number, lng: number }) => {
  const link = document.getElementById('nav-rss') as HTMLAnchorElement | null;
  if (link) link.href = `/feed/${position.lng.toFixed(6)}/${position.lat.toFixed(6)}`;
};

export const setupNavigation = () => {
  const header = document.getElementById('site-header');
  const toggle = document.getElementById('nav-toggle');
  const panel = document.getElementById('nav-panel');
  if (!header || !toggle || !panel) return;

  updateFeedLink(storedMapPosition() || DEFAULT_POSITION);

  const behind = () => Array.from(document.querySelectorAll<HTMLElement>('.layout > :not(header)'));

  const setOpen = (open: boolean) => {
    header.toggleAttribute('data-nav-open', open);
    toggle.setAttribute('aria-expanded', String(open));
    document.documentElement.classList.toggle('nav-open', open);
    behind().forEach((element) => { element.inert = open; });
  };

  toggle.addEventListener('click', () => {
    const open = !header.hasAttribute('data-nav-open');
    setOpen(open);
    // the panel becomes visible with the next frame, only then it can get the focus
    if (open) {
      window.requestAnimationFrame(() => {
        window.requestAnimationFrame(() => panel.querySelector<HTMLElement>('a')?.focus());
      });
    }
  });

  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape' && header.hasAttribute('data-nav-open')) {
      setOpen(false);
      toggle.focus();
    }
  });

  // the menu is part of the normal header again on larger screens
  window.matchMedia('(max-width: 50rem)').addEventListener('change', (query) => {
    if (!query.matches) setOpen(false);
  });
};
