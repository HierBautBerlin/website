import * as maplibregl from 'maplibre-gl';
import type {
  ExpressionSpecification, FilterSpecification, MapGeoJSONFeature, MapLayerMouseEvent,
} from 'maplibre-gl';
import { ViewHook } from 'phoenix_live_view';
import { MAP_STYLE } from './mapStyle';
import { storeMapPosition } from './storage';
import { updateFeedLink } from './navigation';
import { FLY_TO_EVENT, type FlyToDetail } from './searchCombobox';

type ItemProperties = {
  item_id: number,
  item_type: string,
  title: string,
  date?: string,
};

const ITEM_LAYERS = ['polygons', 'lines', 'circles'];
const VIEWPORT_DEBOUNCE_MS = 250;
const LIST_WIDTH_PADDING = 416;
// the list slides down in 0.35s (map.scss), the toolbar keeps this distance to the bottom
const LIST_TOGGLE_MS = 350;
const COLLAPSED_LIST_MARGIN = 24;
// The center of Berlin, used when the page has no position
const DEFAULT_CENTER = { lat: 52.5166309, lng: 13.3781537, zoom: 15 };

const numberOr = (value: string | undefined, fallback: number) => {
  const number = parseFloat(value || '');
  return Number.isFinite(number) ? number : fallback;
};

const matchesItem = (type: string, id: number): ExpressionSpecification => [
  'all',
  ['==', ['get', 'item_type'], type],
  ['==', ['get', 'item_id'], id],
];

const NO_ITEM: FilterSpecification = ['==', ['get', 'item_id'], -1];

const drawFilter = (...draws: string[]): FilterSpecification => ['in', ['get', 'draw'], ['literal', draws]];

export default class InteractiveMap extends ViewHook {
  map!: maplibregl.Map;

  viewportTimeout?: number;

  popup = new maplibregl.Popup({ closeButton: false, closeOnClick: false, className: 'map--popup' });

  mounted() {
    const mapElement = this.el.querySelector('#map') as HTMLElement;
    const data = this.el.dataset;

    this.map = new maplibregl.Map({
      container: mapElement,
      style: MAP_STYLE,
      center: [numberOr(data.positionLng, DEFAULT_CENTER.lng), numberOr(data.positionLat, DEFAULT_CENTER.lat)],
      zoom: numberOr(data.positionZoom, DEFAULT_CENTER.zoom),
      dragRotate: false,
      pitchWithRotate: false,
    });
    this.map.touchZoomRotate.disableRotation();
    this.updatePadding();

    const centerMarkerElement = document.createElement('div');
    centerMarkerElement.className = 'map--center-marker';
    centerMarkerElement.textContent = '+';
    const centerMarker = new maplibregl.Marker({ element: centerMarkerElement })
      .setLngLat(this.map.getCenter())
      .addTo(this.map);
    this.map.on('move', () => centerMarker.setLngLat(this.map.getCenter()));

    this.map.on('load', () => {
      this.addItemLayers(data.tilesUrl || '', parseInt(data.tilesMinZoom || '11', 10));
      this.applySourceFilter();
      this.pushViewport();
    });
    this.map.on('moveend', () => this.scheduleViewport());

    this.handleEvent('map:list-updated', () => {
      const list = this.el.querySelector('.map--item-list');
      if (list) list.scrollTop = 0;
    });

    this.onResize = this.onResize.bind(this);
    this.onFlyTo = this.onFlyTo.bind(this);
    // the list was collapsed or expanded on a phone (MapLive.list_collapse_toggle/0)
    this.el.addEventListener('hierbautberlin:list-toggled', () => this.updatePadding(true));
    window.addEventListener('resize', this.onResize);

    this.setupDomListeners();
  }

  updated() {
    this.applySourceFilter();
  }

  // Hides the items of the sources that are disabled in the list toolbar
  applySourceFilter() {
    if (!this.map.getLayer('circles')) return;

    let hidden: number[] = [];
    try {
      hidden = JSON.parse(this.el.dataset.hiddenSources || '[]');
    } catch {
      hidden = [];
    }

    const visible = ['!', ['in', ['get', 'source_id'], ['literal', hidden]]];
    const layers: [string, FilterSpecification][] = [
      ['polygons', drawFilter('polygon')],
      ['lines', drawFilter('line')],
      ['circles', drawFilter('circle', 'center')],
    ];

    layers.forEach(([layer, filter]) => {
      this.map.setFilter(layer, (hidden.length > 0 ? ['all', filter, visible] : filter) as FilterSpecification);
    });
  }

  destroyed() {
    window.removeEventListener('resize', this.onResize);
    window.removeEventListener(FLY_TO_EVENT, this.onFlyTo);
    window.clearTimeout(this.viewportTimeout);
    this.map?.remove();
  }

  listCollapsed(): boolean {
    return this.el.querySelector('#list-collapse-button')?.getAttribute('aria-expanded') === 'false';
  }

  onResize() {
    this.updatePadding();
  }

  addItemLayers(tilesUrl: string, minzoom: number) {
    const { map } = this;

    map.addSource('items', {
      type: 'vector',
      // no new URL() here, it would encode the {z}/{x}/{y} placeholders
      tiles: [`${window.location.origin}${tilesUrl}`],
      minzoom,
      maxzoom: 16,
    });

    map.addLayer({
      id: 'polygons',
      type: 'fill',
      source: 'items',
      'source-layer': 'items',
      filter: drawFilter('polygon'),
      paint: {
        'fill-color': ['get', 'color'],
        'fill-opacity': 0.5,
        'fill-outline-color': '#ffffff',
      },
    });

    map.addLayer({
      id: 'lines',
      type: 'line',
      source: 'items',
      'source-layer': 'items',
      filter: drawFilter('line'),
      layout: { 'line-join': 'round', 'line-cap': 'round' },
      paint: {
        'line-color': ['get', 'color'],
        'line-width': 6,
        'line-opacity': 0.5,
      },
    });

    map.addLayer({
      id: 'circles',
      type: 'circle',
      source: 'items',
      'source-layer': 'items',
      filter: drawFilter('circle', 'center'),
      paint: {
        'circle-color': ['get', 'color'],
        'circle-radius': ['interpolate', ['linear'], ['zoom'], 11, 4, 14, 8],
        'circle-stroke-width': ['interpolate', ['linear'], ['zoom'], 11, 1, 14, 2],
        'circle-stroke-color': '#ffffff',
      },
    });

    // Highlight of the item the user hovers in the list
    map.addLayer({
      id: 'highlight-lines',
      type: 'line',
      source: 'items',
      'source-layer': 'items',
      filter: NO_ITEM,
      paint: { 'line-color': '#000000', 'line-width': 3 },
    });

    map.addLayer({
      id: 'highlight-circles',
      type: 'circle',
      source: 'items',
      'source-layer': 'items',
      filter: NO_ITEM,
      paint: {
        'circle-color': ['get', 'color'],
        'circle-radius': 12,
        'circle-stroke-width': 3,
        'circle-stroke-color': '#000000',
      },
    });

    ITEM_LAYERS.forEach((layer) => {
      map.on('mouseenter', layer, () => { map.getCanvas().style.cursor = 'pointer'; });
      map.on('mouseleave', layer, () => { map.getCanvas().style.cursor = ''; });
    });

    map.on('mousemove', 'circles', (event) => this.showPopup(event));
    map.on('mouseleave', 'circles', () => this.popup.remove());

    // Only handle the top most feature, even if several layers are hit
    map.on('click', (event) => {
      const [feature] = map.queryRenderedFeatures(event.point, { layers: ['circles', 'lines', 'polygons'] });
      if (feature) this.showDetails(feature);
    });
  }

  showPopup(event: MapLayerMouseEvent) {
    const feature = event.features?.[0];
    if (!feature || feature.geometry.type !== 'Point') return;

    const properties = feature.properties as ItemProperties;
    const [lng, lat] = feature.geometry.coordinates;
    // built from elements, the title must not be interpreted as HTML
    const content = document.createElement('div');
    const title = document.createElement('div');
    title.className = 'map--popup--title';
    title.textContent = properties.title;
    content.appendChild(title);

    if (properties.date) {
      const date = document.createElement('div');
      date.className = 'map--popup--date';
      date.textContent = properties.date;
      content.appendChild(date);
    }

    this.popup.setLngLat({ lng, lat }).setDOMContent(content).addTo(this.map);
  }

  showDetails(feature: MapGeoJSONFeature) {
    const properties = feature.properties as ItemProperties;
    this.pushEvent('showDetails', { 'item-id': properties.item_id, 'item-type': properties.item_type });
  }

  highlightItem(type: string | null, id: number | null) {
    if (!this.map.getLayer('highlight-circles')) return;

    const filter = type && id ? matchesItem(type, id) : NO_ITEM;
    this.map.setFilter('highlight-circles', ['all', filter, drawFilter('circle', 'center')] as FilterSpecification);
    this.map.setFilter('highlight-lines', ['all', filter, drawFilter('line', 'polygon')] as FilterSpecification);
  }

  scheduleViewport() {
    window.clearTimeout(this.viewportTimeout);
    this.viewportTimeout = window.setTimeout(() => this.pushViewport(), VIEWPORT_DEBOUNCE_MS);
  }

  pushViewport() {
    const { map } = this;
    const padding = map.getPadding();
    const canvas = map.getCanvas();
    const topLeft = map.unproject([padding.left ?? 0, padding.top ?? 0]);
    const bottomRight = map.unproject([
      canvas.clientWidth - (padding.right ?? 0),
      canvas.clientHeight - (padding.bottom ?? 0),
    ]);
    const center = map.getCenter();
    storeMapPosition({ lat: center.lat, lng: center.lng, zoom: map.getZoom() });
    updateFeedLink(center);

    const loadingTimeout = window.setTimeout(() => {
      window.dispatchEvent(new Event('phx:page-loading-start'));
    }, 300);

    this.pushEvent('viewport', {
      center: { lat: center.lat, lng: center.lng },
      zoom: map.getZoom(),
      bounds: {
        west: topLeft.lng,
        north: topLeft.lat,
        east: bottomRight.lng,
        south: bottomRight.lat,
      },
    }, () => {
      window.clearTimeout(loadingTimeout);
      window.dispatchEvent(new Event('phx:page-loading-stop'));
    });
  }

  // The map center is the middle of the area that isn't covered by the list
  updatePadding(animate = false) {
    let padding = {
      right: LIST_WIDTH_PADDING, top: 0, left: 0, bottom: 0,
    };

    if (window.innerWidth <= 800) {
      // aria-expanded is set right away, LiveView adds the class in the next frame
      const collapsed = this.listCollapsed();
      const toolbar = this.el.querySelector<HTMLElement>('.map--list-toolbar');
      const bottom = collapsed && toolbar
        ? toolbar.offsetHeight + COLLAPSED_LIST_MARGIN
        : window.innerHeight / 2 + window.innerHeight / 100;
      padding = {
        right: 0, top: 0, left: 0, bottom,
      };
    }

    if (animate) {
      // moves the map with the list, moveend loads the items of the new area
      this.map.easeTo({ padding, duration: LIST_TOGGLE_MS });
    } else {
      this.map.setPadding(padding);
    }
  }

  onFlyTo(event: Event) {
    const { lat, lng } = (event as CustomEvent<FlyToDetail>).detail;
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) return;

    this.map.flyTo({
      center: { lat, lng },
      zoom: 14.5,
      curve: 0.4,
      maxDuration: 1400,
    });
  }

  setupDomListeners() {
    // A street was selected in the search
    window.addEventListener(FLY_TO_EVENT, this.onFlyTo);

    this.el.addEventListener('click', (event) => {
      const target = event.target as HTMLElement;

      // Links in the list only exist for crawlers and "open in new tab", a normal
      // click is handled by phx-click on the list item.
      if (target.closest('[data-details-link]')) {
        event.preventDefault();
      }
    });

    const list = this.el.querySelector('.map--item-list');
    list?.addEventListener('mouseover', (event) => {
      const item = (event.target as HTMLElement).closest<HTMLElement>('[data-item-id]');
      if (item) this.highlightItem(item.dataset.itemType || null, parseInt(item.dataset.itemId || '', 10));
    });
    list?.addEventListener('mouseleave', () => this.highlightItem(null, null));

    const locationButton = this.el.querySelector<HTMLButtonElement>('#map-location-button');
    locationButton?.addEventListener('click', () => {
      if (!navigator.geolocation) return;

      navigator.geolocation.getCurrentPosition((position) => {
        this.map.flyTo({
          center: { lat: position.coords.latitude, lng: position.coords.longitude },
          zoom: 14.5,
          curve: 0.4,
          maxDuration: 1400,
        });
      }, () => {
        locationButton.setAttribute('disabled', 'disabled');
      });
    });
  }
}
