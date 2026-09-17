// The viewer components of PDF.js (legacy/web/pdf_viewer.mjs) read the
// library from globalThis, so this has to be imported before them.
//
// We use the legacy build everywhere (library, viewer components and worker).
// The default build uses JS features that current browsers do not have yet,
// e.g. Map.prototype.getOrInsertComputed (crashes in Chrome) and
// Math.sumPrecise; the legacy build ships the polyfills for them.
import * as pdfjsLib from 'pdfjs-dist/legacy/build/pdf.mjs';

(globalThis as unknown as { pdfjsLib: typeof pdfjsLib }).pdfjsLib = pdfjsLib;

pdfjsLib.GlobalWorkerOptions.workerSrc = '/js/pdf.worker.bundle.js';
