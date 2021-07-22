import mapboxgl, {
  Map, LngLatLike, GeoJSONSource,
} from 'mapbox-gl';
import { ViewHook } from 'phoenix_live_view';
import { isEqual, uniq } from 'lodash-es';

type Geometry = {
  type: string,
  coordinates?: number[],
  geometries?: Geometry[],
  crs: {
    properties: Record<string, string>
  }
};

type GeoItem = {
  id: number
  type: string,
  title: string,
  source_color: string,
  positions: GeoPosition[]
};

type GeoPosition = {
  id: number,
  type: string,
  point: Geometry
  geometry: Geometry
};

type ItemProperties = {
  itemId: number,
  itemType: string,
};

const url = new URL(window.location.href);
url.searchParams.get('c');

let map:Map;

const centerMarkerElement = document.createElement('div');
centerMarkerElement.className = 'marker';
centerMarkerElement.innerHTML = '+';
centerMarkerElement.style.fontSize = '30px';
centerMarkerElement.style.color = '#6f6f6f';
centerMarkerElement.style.width = '20px';
centerMarkerElement.style.height = '20px';
const centerMarker = new mapboxgl.Marker(centerMarkerElement);

const isLineString = (item: Geometry) => {
  const collectionType = uniq(item.geometries?.map((geometry) => geometry.type));
  return item.type === 'LineString' || isEqual(collectionType, ['LineString']);
};

const updateMapItems = () => {
  document.querySelectorAll("[data-hook='open-position']").forEach((link) => {
    link.addEventListener('click', (event) => {
      event.preventDefault();
      const lat = parseFloat(link.getAttribute('data-lat') || '');
      const lng = parseFloat(link.getAttribute('data-lng') || '');
      map.flyTo({
        center: { lng, lat }, zoom: 14.5, curve: 0.4, maxDuration: 1400,
      });
    });
  });

  const mapItems = JSON.parse(document.getElementById('map-data')?.innerHTML || '{}')?.items;

  const mapFeatures:any[] = [];

  mapItems.forEach((item:GeoItem) => {
    item.positions.forEach((position) => {
      if (position.point) {
        mapFeatures.push({
          type: 'Feature',
          properties: {
            itemId: item.id,
            itemType: item.type,
            color: item.source_color,
            draw: 'circle',
          },
          geometry: position.point,
        });
      }

      if (item.type === 'geo_item' && position.geometry) {
        if (isLineString(position.geometry)) {
          mapFeatures.push({
            type: 'Feature',
            properties: {
              itemId: item.id,
              itemType: item.type,
              color: item.source_color,
              draw: 'line',
            },
            geometry: position.geometry,
          });
        } else {
          mapFeatures.push({
            type: 'Feature',
            properties: {
              itemId: item.id,
              itemType: item.type,
              color: item.source_color,
              draw: 'polygon',
            },
            geometry: position.geometry,
          });
        }
      }
    });
  });
  const source = map.getSource('items') as GeoJSONSource;
  source.setData({
    type: 'FeatureCollection',
    features: mapFeatures,
  });
};

const resetMapPadding = () => {
  if (window.innerWidth > 800) {
    map.setPadding({
      right: 416,
      top: 0,
      left: 0,
      bottom: 0,
    });
  } else {
    map.setPadding({
      right: 0,
      top: 0,
      left: 0,
      bottom: window.innerHeight / 2 + window.innerHeight / 100,
    });
  }
};

const InteractiveMap = {
  mounted() {
    const hook = this as unknown as ViewHook;
    const mapElement = document.getElementById('map');

    const position:LngLatLike = [
      parseFloat(mapElement?.getAttribute('data-position-lng') || '0'),
      parseFloat(mapElement?.getAttribute('data-position-lat') || '0'),
    ];

    map = new mapboxgl.Map({
      container: 'map',
      style: 'mapbox://styles/mapbox/streets-v11',
      center: position,
      zoom: parseFloat(mapElement?.getAttribute('data-position-zoom') || '14.5'),
      dragRotate: false,
      pitchWithRotate: false,
    });

    // disable map rotation using touch rotation gesture
    map.touchZoomRotate.disableRotation();

    map.on('load', () => {
      map.addSource('items', { type: 'geojson', data: { type: 'FeatureCollection', features: [] } });
      updateMapItems();

      map.addLayer({
        id: 'lines',
        type: 'line',
        source: 'items',
        layout: {
          'line-join': 'round',
          'line-cap': 'round',
        },
        paint: {
          'line-color': ['get', 'color'],
          'line-width': 6,
          'line-opacity': 0.4,
        },
        filter: ['==', 'draw', 'line'],
      });

      map.on('mouseenter', 'lines', () => {
        map.getCanvas().style.cursor = 'pointer';
      });

      // Change it back to a pointer when it leaves.
      map.on('mouseleave', 'lines', () => {
        map.getCanvas().style.cursor = '';
      });

      map.on('click', 'lines', (e) => {
        if (e.features) {
          const properties = e.features[0].properties as ItemProperties;
          hook.pushEvent('showDetails', { 'item-id': properties.itemId, 'item-type': properties.itemType });
          e.preventDefault();
        }
      });

      map.addLayer({
        id: 'polygons',
        type: 'fill',
        source: 'items',
        paint: {
          'fill-color': ['get', 'color'],
          'fill-opacity': 0.4,
          'fill-outline-color': '#ffffff',
        },
        filter: ['==', 'draw', 'polygon'],
      });

      map.on('mouseenter', 'polygons', () => {
        map.getCanvas().style.cursor = 'pointer';
      });

      // Change it back to a pointer when it leaves.
      map.on('mouseleave', 'polygons', () => {
        map.getCanvas().style.cursor = '';
      });

      map.on('click', 'polygons', (e) => {
        if (e.features) {
          const properties = e.features[0].properties as ItemProperties;
          hook.pushEvent('showDetails', { 'item-id': properties.itemId, 'item-type': properties.itemType });
          e.preventDefault();
        }
      });

      map.addLayer({
        id: 'circle',
        type: 'circle',
        source: 'items',
        paint: {
          'circle-color': ['get', 'color'],
          'circle-radius': 8,
          'circle-stroke-width': 2,
          'circle-stroke-color': '#ffffff',
        },
        filter: ['==', 'draw', 'circle'],
      });
      map.on('mouseenter', 'circle', () => {
        map.getCanvas().style.cursor = 'pointer';
      });

      // Change it back to a pointer when it leaves.
      map.on('mouseleave', 'circle', () => {
        map.getCanvas().style.cursor = '';
      });

      map.on('click', 'circle', (e) => {
        if (e.features) {
          const properties = e.features[0].properties as ItemProperties;
          hook.pushEvent('showDetails', { 'item-id': properties.itemId, 'item-type': properties.itemType });
          e.preventDefault();
        }
      });

      centerMarker.setLngLat(map.getCenter()).addTo(map);
      map.on('move', () => {
        centerMarker.setLngLat(map.getCenter()).addTo(map);
      });

      resetMapPadding();
      window.addEventListener('resize', resetMapPadding);

      map.on('zoomend', () => {
        hook.pushEvent('updateZoom', { zoom: map.getZoom() });
      });
      map.on('moveend', () => {
        hook.pushEvent('updateCoordinates', map.getCenter());
      });
    });

    const locationButton = document.getElementById('map-location-button');
    locationButton?.addEventListener('click', () => {
      if (navigator.geolocation) {
        navigator.geolocation.getCurrentPosition((item) => {
          const newMapPosition = { lat: item.coords.latitude, lng: item.coords.longitude };
          map.flyTo({
            center: newMapPosition, zoom: 14.5, curve: 0.4, maxDuration: 1400,
          });
        }, () => {
          locationButton.setAttribute('disabled', 'disabled');
        });
      }
    });
  },

  updated() {
    updateMapItems();
  },
};

export default InteractiveMap;
