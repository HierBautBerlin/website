import * as pdfjsLib from 'pdfjs-dist';

// Setting worker path to worker bundle.
pdfjsLib.GlobalWorkerOptions.workerSrc = '/js/pdf.worker.bundle.js';

const canvas = document.getElementById('pdf-canvas');
const pdfPath = canvas.getAttribute('data-pdf-path');

const searchParams = new URLSearchParams(window.location.search);

let pdfDoc = null;
let pageNum = parseInt(searchParams.get('page'), 10) || 1;
let pageRendering = false;
let pageNumPending = null;

/**
 * Get page info from document, resize canvas accordingly, and render page.
 * @param num Page number.
 */
function renderPage(num) {
  const ctx = canvas.getContext('2d');
  pageRendering = true;
  // Using promise to fetch the page
  pdfDoc.getPage(num).then((page) => {
    const viewport = page.getViewport({
      scale: canvas.clientWidth / page.getViewport({ scale: 1.0 }).width,
    });
    canvas.height = viewport.height;
    canvas.width = viewport.width;

    // Render PDF page into canvas context
    const renderContext = {
      canvasContext: ctx,
      viewport,
    };
    const renderTask = page.render(renderContext);

    page.getTextContent().then((textContent) => {
      const textlayer = document.getElementById('pdf-text');
      textlayer.innerHTML = '';
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

  // Update page counters
  document.getElementById('pdf-number').textContent = `${num} / ${pdfDoc.numPages}`;
}

/**
 * If another page rendering in progress, waits until the rendering is
 * finised. Otherwise, executes rendering immediately.
 */
function queueRenderPage(num) {
  if (pageRendering) {
    pageNumPending = num;
  } else {
    renderPage(num);
  }
}

/**
 * Displays previous page.
 */
function onPrevPage() {
  if (pageNum <= 1) {
    return;
  }
  pageNum -= 1;
  queueRenderPage(pageNum);
}

/**
 * Displays next page.
 */
function onNextPage() {
  if (pageNum >= pdfDoc.numPages) {
    return;
  }
  pageNum += 1;
  queueRenderPage(pageNum);
}

document.addEventListener('DOMContentLoaded', () => {
  document.getElementById('pdf-prev').addEventListener('click', onPrevPage);
  document.getElementById('pdf-next').addEventListener('click', onNextPage);
  pdfjsLib.getDocument(pdfPath).promise.then((pdfDoc_) => {
    pdfDoc = pdfDoc_;
    document.getElementById('pdf-number').textContent = pdfDoc.numPages;

    // Initial/first page rendering
    renderPage(pageNum);
  });

  window.addEventListener('resize', () => queueRenderPage(pageNum));
});
