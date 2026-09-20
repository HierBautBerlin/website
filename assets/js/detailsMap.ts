import * as maplibregl from 'maplibre-gl';
import type { FilterSpecification } from 'maplibre-gl';
import { ViewHook } from 'phoenix_live_view';
import { MAP_STYLE } from './mapStyle';
import { webglSupported } from './mapSupport';

type Position = [number, number];
type Coordinates = Position | Coordinates[];
type ShapeGeometry = { type: string, coordinates?: Coordinates };
type Shape = {
  type: 'FeatureCollection',
  features: { type: 'Feature', geometry: ShapeGeometry, properties: { draw: string } }[],
};

const isPosition = (coordinates: Coordinates): coordinates is Position => typeof coordinates[0] === 'number';

// all positions of points, lines and (multi) polygons
const extendBounds = (bounds: maplibregl.LngLatBounds, coordinates: Coordinates) => {
  if (isPosition(coordinates)) {
    bounds.extend(coordinates);
  } else {
    coordinates.forEach((child) => extendBounds(bounds, child));
  }
};

const drawn = (draw: string): FilterSpecification => ['==', ['get', 'draw'], draw];

// The small map in the details: the shape of the entry (polygons, lines and
// points, MapFeatures.details_shape/1) in the colors of its source, like on the
// big map. It can be moved and zoomed with the buttons, the scroll wheel keeps
// scrolling the dialog.
export default class DetailsMap extends ViewHook {
  map?: maplibregl.Map;

  mounted() {
    let shape: Shape | null = null;
    try {
      shape = JSON.parse(this.el.dataset.shape || 'null');
    } catch {
      shape = null;
    }
    if (!shape || shape.features.length === 0) return;

    const color = this.el.dataset.color || '#2f7d65';
    const backgroundColor = this.el.dataset.backgroundColor || color;

    const bounds = new maplibregl.LngLatBounds();
    shape.features.forEach((feature) => {
      if (feature.geometry.coordinates) extendBounds(bounds, feature.geometry.coordinates);
    });
    if (bounds.isEmpty()) return;
    // the details work without the small map, so it is simply left out
    if (!webglSupported()) return;

    this.map = new maplibregl.Map({
      container: this.el,
      style: MAP_STYLE,
      bounds,
      fitBoundsOptions: { padding: 40, maxZoom: 15 },
      scrollZoom: false,
      dragRotate: false,
      pitchWithRotate: false,
      attributionControl: { compact: true },
    });
    this.map.touchZoomRotate.disableRotation();
    this.map.addControl(new maplibregl.NavigationControl({ showCompass: false }), 'top-right');

    const data = shape;
    this.map.on('load', () => {
      const { map } = this;
      if (!map) return;

      this.el.querySelector('.maplibregl-ctrl-attrib')?.classList.remove('maplibregl-compact-show');

      map.addSource('details-shape', { type: 'geojson', data: data as GeoJSON.FeatureCollection });

      map.addLayer({
        id: 'details-polygons',
        type: 'fill',
        source: 'details-shape',
        filter: drawn('polygon'),
        paint: { 'fill-color': backgroundColor, 'fill-opacity': 0.4 },
      });

      map.addLayer({
        id: 'details-polygon-outlines',
        type: 'line',
        source: 'details-shape',
        filter: drawn('polygon'),
        paint: { 'line-color': backgroundColor, 'line-width': 2 },
      });

      map.addLayer({
        id: 'details-lines',
        type: 'line',
        source: 'details-shape',
        filter: drawn('line'),
        layout: { 'line-join': 'round', 'line-cap': 'round' },
        paint: { 'line-color': backgroundColor, 'line-width': 6, 'line-opacity': 0.7 },
      });

      map.addLayer({
        id: 'details-points',
        type: 'circle',
        source: 'details-shape',
        filter: drawn('point'),
        paint: {
          'circle-color': color,
          'circle-radius': 8,
          'circle-stroke-width': 2,
          'circle-stroke-color': '#ffffff',
        },
      });
    });
  }

  destroyed() {
    this.map?.remove();
  }
}
