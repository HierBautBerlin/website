import * as maplibregl from 'maplibre-gl';
import { ViewHook } from 'phoenix_live_view';
import circle from '@turf/circle';
import { MAP_STYLE } from './mapStyle';

// A map with the radius of a subscription, the circle follows the radius select.
// Returns a function that removes the map again.
const mountSubscriptionMap = (el: HTMLElement) => {
  const container = el.querySelector<HTMLElement>('.map-details--map');
  const radiusSelect = el.querySelector<HTMLSelectElement>('select');
  if (!container) return () => {};

  const lat = parseFloat(el.dataset.lat || '');
  const lng = parseFloat(el.dataset.lng || '');
  let radius = parseInt(el.dataset.radius || '', 10);
  if (![lat, lng, radius].every(Number.isFinite)) return () => {};

  const map = new maplibregl.Map({
    container,
    style: MAP_STYLE,
    center: [lng, lat],
    zoom: 14,
    attributionControl: { compact: true },
  });

  const paintRadius = () => {
    const radiusCircle = circle([lng, lat], radius / 1000, { steps: 80, units: 'kilometers' });

    const source = map.getSource('radius') as maplibregl.GeoJSONSource | undefined;
    if (source) {
      source.setData(radiusCircle);
    } else {
      map.addSource('radius', { type: 'geojson', data: radiusCircle });
      map.addLayer({
        id: 'radius-fill',
        type: 'fill',
        source: 'radius',
        paint: { 'fill-color': 'red', 'fill-opacity': 0.3 },
      });
    }

    const bounds = new maplibregl.LngLatBounds();
    radiusCircle.geometry.coordinates[0].forEach(([coordLng, coordLat]) => bounds.extend([coordLng, coordLat]));
    map.fitBounds(bounds, { padding: 20 });
  };

  const onRadiusChange = () => {
    radius = parseInt(radiusSelect?.value || '', 10);
    if (Number.isFinite(radius) && map.isStyleLoaded()) paintRadius();
  };

  map.on('load', () => {
    // the small map starts with the attribution collapsed, it opens with the (i) button
    container.querySelector('.maplibregl-ctrl-attrib')?.classList.remove('maplibregl-compact-show');
    paintRadius();
  });
  radiusSelect?.addEventListener('change', onRadiusChange);

  return () => {
    radiusSelect?.removeEventListener('change', onRadiusChange);
    map.remove();
  };
};

// In LiveViews (the subscription dialog on the map)
export default class SubscriptionMap extends ViewHook {
  unmount?: () => void;

  mounted() {
    this.unmount = mountSubscriptionMap(this.el);
  }

  destroyed() {
    this.unmount?.();
  }
}

// On normal pages (the list of subscriptions in the settings)
export const setupSubscriptionMaps = () => {
  document.querySelectorAll<HTMLElement>('[data-subscription-map]:not([phx-hook])').forEach((el) => {
    mountSubscriptionMap(el);
  });
};
