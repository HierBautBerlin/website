import mapboxgl from 'mapbox-gl';
import { Controller } from 'stimulus';
import * as turf from '@turf/turf';
import { Position } from '@turf/turf';

export default class extends Controller {
  declare readonly mapTarget: HTMLElement;

  declare readonly radiusTarget: HTMLSelectElement;

  static targets = ['map', 'radius'];

  declare latValue: number;

  declare lngValue: number;

  declare radiusValue: number;

  static values = {
    lat: Number,
    lng: Number,
    radius: Number,
  };

  declare map: mapboxgl.Map;

  connect() {
    this.map = new mapboxgl.Map({
      container: this.mapTarget,
      style: 'mapbox://styles/mapbox/streets-v11',
      center: [this.lngValue, this.latValue],
      zoom: 14,
    });
    this.map.on('load', () => {
      this.repaintMap();
    });
    this.radiusTarget.addEventListener('change', (event) => {
      const target = event.target as HTMLSelectElement;
      this.radiusValue = parseInt(target.options[target.selectedIndex].value, 10);
      this.repaintMap();
    });
  }

  repaintMap() {
    if (this.map.getSource('circleData')) {
      this.map.removeLayer('circle-fill');
      this.map.removeSource('circleData');
    }
    const center = turf.point([this.lngValue, this.latValue]);
    const radius = this.radiusValue / 1000;
    const circle = turf.circle(center, radius, {
      steps: 80,
      units: 'kilometers',
    });

    this.map.addSource('circleData', {
      type: 'geojson',
      data: circle,
    });

    this.map.addLayer({
      id: 'circle-fill',
      type: 'fill',
      source: 'circleData',
      paint: {
        'fill-color': 'red',
        'fill-opacity': 0.3,
      },
    });

    const convertToLatLng = (coord: Position) => (
      new mapboxgl.LngLat(coord[0], coord[1])
    );

    const coordinates = circle.geometry.coordinates[0];
    const bounds = coordinates.reduce(
      (bound, coord) => bound.extend(convertToLatLng(coord)),
      new mapboxgl.LngLatBounds(
        convertToLatLng(coordinates[0]),
        convertToLatLng(coordinates[0]),
      ),
    );
    this.map.fitBounds(bounds, {
      padding: 20,
    });
  }
}
