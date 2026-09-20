// MapLibre needs a WebGL2 context. Without one `new maplibregl.Map()` does not
// throw, it returns a half built map without painter and handlers, and the next
// call on it fails ("Cannot read properties of undefined (reading
// 'disableRotation')"). So we ask before building one: WebGL can be turned off,
// blocked for the graphics card or missing in a headless browser.
let supported: boolean | undefined;

export const webglSupported = (): boolean => {
  if (supported === undefined) {
    try {
      const context = document.createElement('canvas').getContext('webgl2');
      // browsers only allow a handful of contexts, this one was just for asking
      context?.getExtension('WEBGL_lose_context')?.loseContext();
      supported = !!context;
    } catch {
      supported = false;
    }
  }

  return supported;
};

// Replaces the map with a note about it, the list next to it still works
export const showWebglHint = (element: HTMLElement) => {
  const hint = document.createElement('p');
  hint.className = 'map--webgl-hint';
  hint.textContent = 'Die Karte braucht WebGL, dein Browser kann das nicht oder es ist abgeschaltet.';
  element.replaceChildren(hint);
};
