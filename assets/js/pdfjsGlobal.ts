// The viewer components of PDF.js (pdfjs-dist/web/pdf_viewer.mjs) read the
// library from globalThis, so this has to be imported before them.
import * as pdfjsLib from 'pdfjs-dist';

(globalThis as unknown as { pdfjsLib: typeof pdfjsLib }).pdfjsLib = pdfjsLib;

pdfjsLib.GlobalWorkerOptions.workerSrc = '/js/pdf.worker.bundle.js';
