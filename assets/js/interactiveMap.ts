import mapboxgl, { Map, LngLatLike, Marker } from 'mapbox-gl';
import { ViewHook } from 'phoenix_live_view';
import { difference, isEqual, uniq } from 'lodash-es';

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
  positions: GeoPosition[]
};

type GeoPosition = {
  id: number,
  type: string,
  point: Geometry
  geometry: Geometry
};

const url = new URL(window.location.href);
url.searchParams.get('c');

let map:Map;
interface MapObject {
  marker?: Marker,
  layerName?: string
  item: GeoItem
}

const mapObjects: {
  [key: number] : MapObject
} = {};

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

const removeUneededMapItems = (mapIds: number[]) => {
  difference<number>(Object.keys(mapObjects).map(Number), mapIds).forEach((itemId: number) => {
    if (mapObjects[itemId].marker) {
      mapObjects[itemId].marker?.remove();
    }
    if (mapObjects[itemId].layerName) {
      const name = mapObjects[itemId].layerName || '';
      map.removeLayer(name);
      if (map.getLayer(`${name}-outline`)) {
        map.removeLayer(`${name}-outline`);
      }
      map.removeSource(name);
    }

    delete mapObjects[itemId];
  });
};

const addMarkerForPoint = (hook: ViewHook, position: GeoPosition) => {
  const marker = new mapboxgl.Marker()
    .setLngLat(position.point.coordinates as LngLatLike)
    .addTo(map);

  marker.getElement().addEventListener('click', (event) => {
    hook.pushEvent('showDetails', { 'item-id': position.id, 'item-type': position.type });
    event.preventDefault();
  });
  return marker;
};

const addLayerForGeometry = (layerName:string, position:GeoPosition) => {
  map.addSource(layerName, {
    type: 'geojson',
    data: position.geometry as any,
  });

  if (isLineString(position.geometry)) {
    map.addLayer({
      id: layerName,
      type: 'line',
      source: layerName, // reference the data source
      layout: {
        'line-join': 'round',
        'line-cap': 'round',
      },
      paint: {
        'line-color': '#888',
        'line-width': 8,
      },
    });
  } else {
    map.addLayer({
      id: layerName,
      type: 'fill',
      source: layerName, // reference the data source
      layout: {},
      paint: {
        'fill-color': '#0080ff', // blue color fill
        'fill-opacity': 0.5,
      },
    });
    // Add a black outline around the polygon.
    map.addLayer({
      id: `${layerName}-outline`,
      type: 'line',
      source: layerName, // reference the data source
      layout: {},
      paint: {
        'line-color': '#000',
        'line-width': 2,
      },
    });
  }
};

const updateMapItems = (hook: ViewHook) => {
  const mapItems = JSON.parse(document.getElementById('map-data')?.innerHTML || '{}')?.items;
  const mapIds:number[] = mapItems.map((item:GeoItem) => item.id);

  removeUneededMapItems(mapIds);

  mapItems.forEach((item:GeoItem) => {
    if (!mapObjects[item.id]) {
      const mapItem:MapObject = {
        item,
      };
      mapObjects[item.id] = mapItem;

      item.positions.forEach((position) => {
        if (position.point) {
          mapItem.marker = addMarkerForPoint(hook, position);
        }

        if (item.type === 'geo_item' && position.geometry) {
          const layerName = `map-item-${position.id}`;
          mapItem.layerName = layerName;
          addLayerForGeometry(layerName, position);
        }
      });
    }
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
    });

    map.on('load', () => {
      updateMapItems(hook);
    });

    resetMapPadding();
    window.addEventListener('resize', resetMapPadding);

    map.on('zoomend', () => {
      hook.pushEvent('updateZoom', { zoom: map.getZoom() });
    });
    map.on('moveend', () => {
      hook.pushEvent('updateCoordinates', map.getCenter());
    });

    centerMarker.setLngLat(map.getCenter()).addTo(map);
    map.on('move', () => {
      centerMarker.setLngLat(map.getCenter()).addTo(map);
    });

    map.on('click', (e) => {
      if (!e.originalEvent.defaultPrevented) {
        const layers = map.queryRenderedFeatures(e.point);

        if (layers[0]) {
          const match = layers[0].source.match(/map-item-(\d*)/);
          if (match) {
            const itemId = parseInt(match[1], 10);
            hook.pushEvent('showDetails', { 'item-id': itemId });
          }
        }
      }
    });

    const locationButton = document.getElementById('map-location-button');
    locationButton?.addEventListener('click', () => {
      if (navigator.geolocation) {
        navigator.geolocation.getCurrentPosition((item) => {
          const newMapPosition = { lat: item.coords.latitude, lng: item.coords.longitude };
          hook.pushEvent('updateCoordinates', newMapPosition);
          map.setCenter(newMapPosition);
          map.setZoom(14.5);
        }, () => {
          locationButton.setAttribute('disabled', 'disabled');
        });
      }
    });
  },
  updated() {
    const hook = this as unknown as ViewHook;
    updateMapItems(hook);
  },
};

export default InteractiveMap;
