import * as pdfjsLib from 'pdfjs-dist';
import type { PDFDocumentProxy } from 'pdfjs-dist';

pdfjsLib.GlobalWorkerOptions.workerSrc = '/js/pdf.worker.bundle.js';

const MIN_ZOOM = 0.2;
const MAX_ZOOM = 2;

const clamp = (min: number, value: number, max: number) => Math.min(max, Math.max(min, value));

const debounce = (fn: () => void, wait: number) => {
  let timeout: number | undefined;
  return () => {
    window.clearTimeout(timeout);
    timeout = window.setTimeout(fn, wait);
  };
};

const byId = <T extends HTMLElement>(id: string) => document.getElementById(id) as T;

const wrapper = document.querySelector('.view-pdf--wrapper') as HTMLElement;
const canvas = byId<HTMLCanvasElement>('pdf-canvas');
const pdfPath = canvas.getAttribute('data-pdf-path') || '';

const searchParams = new URLSearchParams(window.location.search);

let pdfDoc: PDFDocumentProxy;
let pageNum = parseInt(searchParams.get('page') || '', 10) || 1;
let pageRendering = false;
let pageNumPending: number | null = null;
let zoom = 0.8;

const renderPageSelect = (num: number) => {
  const pdfNumberElement = byId('pdf-number');
  pdfNumberElement.innerHTML = '';

  const selectList = document.createElement('select');
  selectList.addEventListener('change', () => {
    pageNum = parseInt(selectList.value, 10);
    // eslint-disable-next-line @typescript-eslint/no-use-before-define
    queueRenderPage(pageNum);
  });
  pdfNumberElement.appendChild(selectList);

  for (let i = 1; i <= pdfDoc.numPages; i += 1) {
    const option = document.createElement('option');
    option.value = String(i);
    option.text = String(i);
    option.selected = num === i;
    selectList.appendChild(option);
  }

  pdfNumberElement.appendChild(document.createTextNode(`/ ${pdfDoc.numPages}`));
};

const renderPage = async (num: number) => {
  pageRendering = true;
  renderPageSelect(num);

  const page = await pdfDoc.getPage(num);
  const scale = (window.innerWidth * zoom) / page.getViewport({ scale: 1.0 }).width;
  const viewport = page.getViewport({ scale });
  const resolution = zoom > 1 ? 1 : window.devicePixelRatio;

  canvas.height = resolution * viewport.height;
  canvas.width = resolution * viewport.width;
  canvas.style.width = `${viewport.width}px`;
  canvas.style.height = `${viewport.height}px`;

  const textLayerElement = byId('pdf-text');
  textLayerElement.innerHTML = '';
  textLayerElement.style.width = `${viewport.width}px`;
  textLayerElement.style.height = `${viewport.height}px`;

  await Promise.all([
    page.render({
      canvas,
      viewport,
      transform: resolution !== 1 ? [resolution, 0, 0, resolution, 0, 0] : undefined,
    }).promise,
    new pdfjsLib.TextLayer({
      textContentSource: page.streamTextContent(),
      container: textLayerElement,
      viewport,
    }).render(),
  ]);

  pageRendering = false;
  if (pageNumPending !== null) {
    const pending = pageNumPending;
    pageNumPending = null;
    renderPage(pending);
  }
};

/**
 * If another page rendering in progress, waits until the rendering is
 * finished. Otherwise, executes rendering immediately.
 */
const queueRenderPage = (num: number) => {
  if (pageRendering) {
    pageNumPending = num;
  } else {
    renderPage(num);
  }
};

const onPrevPage = () => {
  if (pageNum <= 1) return;
  pageNum -= 1;
  queueRenderPage(pageNum);
};

const onNextPage = () => {
  if (pageNum >= pdfDoc.numPages) return;
  pageNum += 1;
  queueRenderPage(pageNum);
};

const onZoomIn = () => {
  zoom = Math.min(MAX_ZOOM, zoom + 0.2);
  queueRenderPage(pageNum);
};

const onZoomOut = () => {
  zoom = Math.max(MIN_ZOOM, zoom - 0.2);
  queueRenderPage(pageNum);
};

const onScale = (el: HTMLElement, touchCallback: (scale: number) => void, startCallback: () => void) => {
  let hypo: number | undefined;

  el.addEventListener('touchstart', () => {
    startCallback();
    hypo = undefined;
  });
  el.addEventListener('touchmove', (event) => {
    if (event.touches.length === 2) {
      const currentHypo = Math.hypot(
        event.touches[0].pageX - event.touches[1].pageX,
        event.touches[0].pageY - event.touches[1].pageY,
      );
      if (hypo === undefined) {
        hypo = currentHypo;
      }
      touchCallback(currentHypo / hypo);
    }
  }, false);
};

const onDownload = () => {
  const link = document.createElement('a');
  link.download = `${pdfPath.split('/').pop()}.pdf`;
  link.href = pdfPath;
  link.click();
};

const init = () => {
  byId('pdf-prev').addEventListener('click', onPrevPage);
  byId('pdf-next').addEventListener('click', onNextPage);
  byId('pdf-zoom-in').addEventListener('click', onZoomIn);
  byId('pdf-zoom-out').addEventListener('click', onZoomOut);
  byId('pdf-download').addEventListener('click', onDownload);

  pdfjsLib.getDocument({ url: pdfPath }).promise.then((doc) => {
    pdfDoc = doc;
    renderPage(pageNum);
  });

  let touchZoom = 0;
  onScale(
    wrapper,
    (scale) => {
      zoom = clamp(MIN_ZOOM, touchZoom * scale, MAX_ZOOM);
      queueRenderPage(pageNum);
    },
    () => {
      touchZoom = zoom;
    },
  );

  window.addEventListener('resize', debounce(() => queueRenderPage(pageNum), 150));
};

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', init);
} else {
  init();
}
