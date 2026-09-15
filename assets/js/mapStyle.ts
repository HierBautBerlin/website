import { setWorkerUrl } from 'maplibre-gl';

// The worker is bundled separately by esbuild (see config/config.exs)
setWorkerUrl('/js/maplibre-gl-worker.bundle.js');

// Free vector tiles without an API key, see https://openfreemap.org
export const MAP_STYLE = 'https://tiles.openfreemap.org/styles/liberty';
