// The PDF viewer (lib/hierbautberlin_web/controllers/view_pdf_html/show.html.heex):
// all pages below each other, rendered by PDF.js when they become visible.
// Zoom with the buttons, the keyboard, pinching on touch screens, double tap or
// ctrl + mouse wheel (pinching on a trackpad).
import './pdfjsGlobal';
import { TouchManager, getDocument } from 'pdfjs-dist';
import { EventBus, PDFLinkService, PDFViewer } from 'pdfjs-dist/web/pdf_viewer.mjs';

const MIN_SCALE = 0.25;
const MAX_SCALE = 5;
const ZOOM_STEP = 1.25;
// while zooming the pages are scaled with CSS, they are drawn again afterwards
const DRAWING_DELAY = 400;
const DOUBLE_TAP_MS = 300;
const DOUBLE_TAP_DISTANCE = 30;

const clamp = (min: number, value: number, max: number) => Math.min(max, Math.max(min, value));

const byId = <T extends HTMLElement>(id: string) => document.getElementById(id) as T;

// aria-disabled instead of disabled: the button keeps the focus (e.g. "next" on
// the last page) and stays readable for screen readers
const setDisabled = (button: HTMLButtonElement, disabled: boolean) => {
  button.setAttribute('aria-disabled', String(disabled));
};

const isDisabled = (button: HTMLButtonElement) => button.getAttribute('aria-disabled') === 'true';

// The texts PDF.js adds to the pages (only the ones this viewer uses), in German.
// Implements the parts of PDF.js' L10n the viewer calls.
const MESSAGES: Record<string, { attribute?: string, text: (args: Record<string, string>) => string }> = {
  'pdfjs-page-landmark': { attribute: 'aria-label', text: ({ page }) => `Seite ${page}` },
  'pdfjs-rendering-error': { text: () => 'Beim Anzeigen der Seite ist ein Fehler aufgetreten.' },
};

const translateElement = (element: Element) => {
  const message = MESSAGES[element.getAttribute('data-l10n-id') || ''];
  if (!message) return;

  let args: Record<string, string> = {};
  try {
    args = JSON.parse(element.getAttribute('data-l10n-args') || '{}');
  } catch {
    args = {};
  }

  if (message.attribute) {
    element.setAttribute(message.attribute, message.text(args));
  } else {
    element.textContent = message.text(args);
  }
};

const translateTree = (root: Element) => {
  translateElement(root);
  root.querySelectorAll('[data-l10n-id]').forEach(translateElement);
};

const germanL10n = () => {
  const observer = new MutationObserver((mutations) => {
    mutations.forEach((mutation) => {
      if (mutation.type === 'attributes') {
        translateElement(mutation.target as Element);
      } else {
        mutation.addedNodes.forEach((node) => {
          if (node instanceof Element) translateTree(node);
        });
      }
    });
  });

  return {
    getLanguage: () => 'de',
    getDirection: () => 'ltr',
    get: async (id: string, args: Record<string, string> | null, fallback: string) => (
      MESSAGES[id]?.text(args || {}) || fallback
    ),
    translate: async (root: Element) => {
      translateTree(root);
      observer.observe(root, {
        subtree: true,
        childList: true,
        attributes: true,
        attributeFilter: ['data-l10n-id', 'data-l10n-args'],
      });
    },
    translateOnce: async (element: Element) => translateTree(element),
    destroy: async () => observer.disconnect(),
    pause: () => {},
    resume: () => {},
  };
};

const init = () => {
  const root = byId('pdf');
  const container = byId<HTMLDivElement>('pdf-container');
  const loading = byId('pdf-loading');
  const loadingText = byId('pdf-loading-text');
  const error = byId('pdf-error');
  const controls = byId('pdf-controls');
  const pageInput = byId<HTMLInputElement>('pdf-page');
  const pageCount = byId('pdf-page-count');
  const prevButton = byId<HTMLButtonElement>('pdf-prev');
  const nextButton = byId<HTMLButtonElement>('pdf-next');
  const zoomOutButton = byId<HTMLButtonElement>('pdf-zoom-out');
  const zoomInButton = byId<HTMLButtonElement>('pdf-zoom-in');
  const zoomResetButton = byId<HTMLButtonElement>('pdf-zoom-reset');
  const announcer = byId('pdf-announcer');

  const l10n = germanL10n();
  const eventBus = new EventBus();
  const linkService = new PDFLinkService({ eventBus });
  const viewer = new PDFViewer({
    container,
    viewer: byId<HTMLDivElement>('pdf-viewer'),
    eventBus,
    linkService,
    // the pages get a shadow in view_pdf.scss instead
    removePageBorders: true,
    l10n: l10n as unknown as ConstructorParameters<typeof PDFViewer>[0]['l10n'],
  });
  linkService.setViewer(viewer);
  l10n.translate(container);

  // Screen readers read the text of the live region when it changes
  const announce = (text: string) => {
    announcer.textContent = '';
    window.requestAnimationFrame(() => { announcer.textContent = text; });
  };

  const percent = (scale: number) => `${Math.round(scale * 100)} %`;
  const pageText = () => `Seite ${viewer.currentPageNumber} von ${viewer.pagesCount}`;
  const announcePage = () => announce(pageText());
  const announceZoom = () => announce(`Größe ${percent(viewer.currentScale)}`);

  // "auto" fits the page width, but not bigger than 125 % on large screens
  let autoScale = 1;
  const isAutoScale = () => viewer.currentScaleValue === 'auto';

  const zoomBy = (factor: number, origin?: [number, number], drawingDelay?: number) => {
    const scale = viewer.currentScale;
    const scaleFactor = clamp(MIN_SCALE, scale * factor, MAX_SCALE) / scale;
    if (Math.abs(scaleFactor - 1) < 0.001) return;
    viewer.updateScale({ scaleFactor, origin, drawingDelay });
  };

  const resetZoom = () => {
    viewer.currentScaleValue = 'auto';
  };

  const goToPage = (page: number) => {
    viewer.currentPageNumber = clamp(1, page, viewer.pagesCount);
  };

  // --- Page and zoom state in the controls and the url

  const updatePage = () => {
    const page = viewer.currentPageNumber;
    if (document.activeElement !== pageInput) pageInput.value = String(page);
    setDisabled(prevButton, page <= 1);
    setDisabled(nextButton, page >= viewer.pagesCount);

    const url = new URL(window.location.href);
    url.searchParams.set('page', String(page));
    window.history.replaceState(window.history.state, '', url);
  };

  const updateZoom = () => {
    const scale = viewer.currentScale;
    zoomResetButton.textContent = percent(scale);
    zoomResetButton.setAttribute('aria-label', `Größe ${percent(scale)}, zurücksetzen`);
    setDisabled(zoomResetButton, isAutoScale());
    setDisabled(zoomOutButton, scale <= MIN_SCALE + 0.001);
    setDisabled(zoomInButton, scale >= MAX_SCALE - 0.001);
  };

  eventBus.on('pagesinit', () => {
    resetZoom();
    autoScale = viewer.currentScale;

    const requested = parseInt(new URLSearchParams(window.location.search).get('page') || '', 10);
    if (requested > 1) goToPage(requested);

    // "/ 13" on the screen, "von 13" for screen readers (the description of the input)
    const visible = document.createElement('span');
    visible.setAttribute('aria-hidden', 'true');
    visible.textContent = `/ ${viewer.pagesCount}`;
    const spoken = document.createElement('span');
    spoken.className = 'visually-hidden';
    spoken.textContent = `von ${viewer.pagesCount}`;
    pageCount.replaceChildren(visible, spoken);
    updatePage();
    updateZoom();

    loading.hidden = true;
    controls.hidden = false;
    root.classList.add('pdf-ready');
  });

  eventBus.on('pagechanging', updatePage);
  eventBus.on('scalechanging', () => {
    if (isAutoScale()) autoScale = viewer.currentScale;
    updateZoom();
  });

  // --- Controls

  const onClick = (button: HTMLButtonElement, action: () => void) => {
    button.addEventListener('click', () => {
      if (!isDisabled(button)) action();
    });
  };

  onClick(prevButton, () => {
    viewer.previousPage();
    announcePage();
  });

  onClick(nextButton, () => {
    viewer.nextPage();
    announcePage();
  });

  const submitPage = () => {
    const page = parseInt(pageInput.value, 10);
    if (Number.isNaN(page)) {
      pageInput.value = String(viewer.currentPageNumber);
      return;
    }
    goToPage(page);
    pageInput.value = String(viewer.currentPageNumber);
    announcePage();
  };

  pageInput.addEventListener('focus', () => pageInput.select());
  pageInput.addEventListener('change', submitPage);
  pageInput.addEventListener('keydown', (event) => {
    if (event.key === 'Enter') {
      event.preventDefault();
      submitPage();
    } else if (event.key === 'Escape') {
      pageInput.value = String(viewer.currentPageNumber);
      pageInput.select();
    }
  });

  onClick(zoomInButton, () => {
    zoomBy(ZOOM_STEP);
    announceZoom();
  });

  onClick(zoomOutButton, () => {
    zoomBy(1 / ZOOM_STEP);
    announceZoom();
  });

  onClick(zoomResetButton, () => {
    resetZoom();
    announceZoom();
  });

  // --- Keyboard: + - 0 zoom, arrows turn the page when it fits the width

  document.addEventListener('keydown', (event) => {
    if (!root.classList.contains('pdf-ready')) return;
    if (event.ctrlKey || event.metaKey || event.altKey || event.defaultPrevented) return;

    const target = event.target as HTMLElement;
    if (target.closest('input, textarea, select, [contenteditable="true"]')) return;

    const fitsWidth = container.scrollWidth <= container.clientWidth + 1;

    switch (event.key) {
      case '+':
      case '=':
        zoomBy(ZOOM_STEP);
        announceZoom();
        break;
      case '-':
        zoomBy(1 / ZOOM_STEP);
        announceZoom();
        break;
      case '0':
        resetZoom();
        announceZoom();
        break;
      case 'ArrowLeft':
        if (!fitsWidth || target.closest('button, a')) return;
        viewer.previousPage();
        announcePage();
        break;
      case 'ArrowRight':
        if (!fitsWidth || target.closest('button, a')) return;
        viewer.nextPage();
        announcePage();
        break;
      default:
        return;
    }
    event.preventDefault();
  });

  // --- Mouse and touch

  // ctrl + wheel, also what browsers send for pinching on a trackpad. A wheel
  // step (100 pixels) zooms by about 28 %, the size is read when it stops.
  let wheelTimeout: number | undefined;
  container.addEventListener('wheel', (event) => {
    if (!event.ctrlKey && !event.metaKey) return;
    event.preventDefault();
    const pixels = event.deltaMode === WheelEvent.DOM_DELTA_LINE ? event.deltaY * 16 : event.deltaY;
    zoomBy(Math.exp(-pixels / 400), [event.clientX, event.clientY], DRAWING_DELAY);
    window.clearTimeout(wheelTimeout);
    wheelTimeout = window.setTimeout(announceZoom, DRAWING_DELAY);
  }, { passive: false });

  // pinching with two fingers, the pages move with the fingers
  const touchController = new AbortController();
  // eslint-disable-next-line no-new
  new TouchManager({
    container,
    isPinchingDisabled: () => !root.classList.contains('pdf-ready'),
    onPinching: (origin: [number, number], previousDistance: number, distance: number) => {
      zoomBy(distance / previousDistance, origin, DRAWING_DELAY);
    },
    onPinchEnd: announceZoom,
    signal: touchController.signal,
  });

  // double tap: zoom in where tapped, the next double tap goes back
  let lastTap = { time: 0, x: 0, y: 0 };
  container.addEventListener('pointerup', (event) => {
    if (event.pointerType !== 'touch' || !event.isPrimary) return;

    const isDoubleTap = event.timeStamp - lastTap.time < DOUBLE_TAP_MS
      && Math.hypot(event.clientX - lastTap.x, event.clientY - lastTap.y) < DOUBLE_TAP_DISTANCE;

    if (!isDoubleTap) {
      lastTap = { time: event.timeStamp, x: event.clientX, y: event.clientY };
      return;
    }

    lastTap = { time: 0, x: 0, y: 0 };
    if (viewer.currentScale > autoScale * 1.2) {
      resetZoom();
    } else {
      zoomBy(2, [event.clientX, event.clientY], DRAWING_DELAY);
    }
    announceZoom();
  });

  // the page width changes with the window (or turning the phone)
  new ResizeObserver(() => {
    if (isAutoScale()) resetZoom();
  }).observe(container);

  // --- Loading

  const task = getDocument({
    url: root.dataset.pdfPath || '',
    // copied from pdfjs-dist by `mix assets.pdfjs`
    wasmUrl: '/pdfjs/wasm/',
    standardFontDataUrl: '/pdfjs/standard_fonts/',
  });

  task.onProgress = ({ loaded, total }: { loaded: number, total: number }) => {
    if (total > 0) loadingText.textContent = `PDF wird geladen … ${Math.round((loaded / total) * 100)} %`;
  };

  task.promise.then((pdfDocument) => {
    viewer.setDocument(pdfDocument);
    linkService.setDocument(pdfDocument);
  }).catch((reason) => {
    console.error('PDF could not be shown', reason);
    loading.hidden = true;
    error.hidden = false;
  });
};

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', init);
} else {
  init();
}
