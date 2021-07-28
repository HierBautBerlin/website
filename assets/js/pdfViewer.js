/* eslint-disable @typescript-eslint/no-use-before-define */
import * as pdfjsLib from 'pdfjs-dist';
import { clamp, debounce } from 'lodash-es';

// Setting worker path to worker bundle.
pdfjsLib.GlobalWorkerOptions.workerSrc = '/js/pdf.worker.bundle.js';

const MIN_ZOOM = 0.2;
const MAX_ZOOM = 2;

const wrapper = document.querySelector('.view-pdf--wrapper');
const canvas = document.getElementById('pdf-canvas');
const pdfPath = canvas.getAttribute('data-pdf-path');

const searchParams = new URLSearchParams(window.location.search);

let pdfDoc = null;
let pageNum = parseInt(searchParams.get('page'), 10) || 1;
let pageRendering = false;
let pageNumPending = null;
let zoom = 0.8;

/**
 * Get page info from document, resize canvas accordingly, and render page.
 * @param num Page number.
 */
const renderPage = (num) => {
  const ctx = canvas.getContext('2d');
  pageRendering = true;
  // Using promise to fetch the page
  pdfDoc.getPage(num).then((page) => {
    const scale = (window.innerWidth * zoom) / page.getViewport({ scale: 1.0 }).width;

    const viewport = page.getViewport({ scale });
    const resolution = zoom > 1 ? 1 : window.devicePixelRatio;

    canvas.height = resolution * viewport.height;
    canvas.width = resolution * viewport.width;

    canvas.style.width = `${viewport.width}px`;
    canvas.style.height = `${viewport.height}px`;

    const context = canvas.getContext('2d');
    context.scale(resolution, resolution);

    // Render PDF page into canvas context
    const renderContext = {
      canvasContext: ctx,
      viewport,
    };
    const renderTask = page.render(renderContext);

    page.getTextContent().then((textContent) => {
      const textlayer = document.getElementById('pdf-text');
      textlayer.innerHTML = '';
      textlayer.style.width = `${viewport.width}px`;
      textlayer.style.height = `${viewport.height}px`;
      pdfjsLib.renderTextLayer({
        textContent,
        container: textlayer,
        viewport,
        textDivs: [],
      });
    });

    // Wait for rendering to finish
    return renderTask.promise.then(() => {
      pageRendering = false;
      if (pageNumPending !== null) {
        // New page rendering is pending
        renderPage(pageNumPending);
        pageNumPending = null;
      }
    });
  });

  const pdfNumberElement = document.getElementById('pdf-number');
  pdfNumberElement.innerHTML = '';

  const selectList = document.createElement('select');
  selectList.addEventListener('change', (event) => {
    pageNum = parseInt(event.target.value, 10);
    queueRenderPage(pageNum);
  });
  pdfNumberElement.appendChild(selectList);

  // Create and append the options
  for (let i = 1; i <= pdfDoc.numPages; i += 1) {
    const option = document.createElement('option');
    option.value = i;
    option.text = i;
    option.selected = num === i;
    selectList.appendChild(option);
  }

  const numberPagesElement = document.createTextNode(`/ ${pdfDoc.numPages}`);
  pdfNumberElement.appendChild(numberPagesElement);
};

/**
 * If another page rendering in progress, waits until the rendering is
 * finised. Otherwise, executes rendering immediately.
 */
const queueRenderPage = (num) => {
  if (pageRendering) {
    pageNumPending = num;
  } else {
    renderPage(num);
  }
};

/**
 * Displays previous page.
 */
const onPrevPage = () => {
  if (pageNum <= 1) {
    return;
  }
  pageNum -= 1;
  queueRenderPage(pageNum);
};

/**
 * Displays next page.
 */
const onNextPage = () => {
  if (pageNum >= pdfDoc.numPages) {
    return;
  }
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

const onScale = (el, touchCallback, startCallback) => {
  let hypo;

  el.addEventListener('touchstart', (_event) => {
    startCallback();
    hypo = undefined;
  });
  el.addEventListener('touchmove', (event) => {
    if (event.touches.length === 2) {
      const hypo1 = Math.hypot((event.touches[0].pageX - event.touches[1].pageX),
        (event.touches[0].pageY - event.touches[1].pageY));
      if (hypo === undefined) {
        hypo = hypo1;
      }
      touchCallback(hypo1 / hypo);
    }
  }, false);
};

const onDownload = () => {
  const link = document.createElement('a');
  link.download = `${pdfPath.split('/').pop()}.pdf`;
  link.href = pdfPath;
  link.click();
};

document.addEventListener('DOMContentLoaded', () => {
  document.getElementById('pdf-prev').addEventListener('click', onPrevPage);
  document.getElementById('pdf-next').addEventListener('click', onNextPage);
  document.getElementById('pdf-zoom-in').addEventListener('click', onZoomIn);
  document.getElementById('pdf-zoom-out').addEventListener('click', onZoomOut);
  document.getElementById('pdf-download').addEventListener('click', onDownload);
  pdfjsLib.getDocument(pdfPath).promise.then((pdfDoc_) => {
    pdfDoc = pdfDoc_;
    document.getElementById('pdf-number').textContent = pdfDoc.numPages;
    renderPage(pageNum);
  });

  let touchZoom = 0;
  onScale(wrapper,
    (scale) => {
      zoom = clamp(MIN_ZOOM, touchZoom * scale, MAX_ZOOM);
      queueRenderPage(pageNum);
    },
    () => {
      touchZoom = zoom;
    });

  window.addEventListener('resize', debounce(() => queueRenderPage(pageNum), 150));
});
