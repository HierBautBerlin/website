import mapboxgl, { LngLatLike, Marker, Popup } from 'mapbox-gl';
import { ViewHookInterface } from 'phoenix_live_view';
import { difference, isEqual, uniq } from 'lodash-es';

mapboxgl.accessToken = 'pk.eyJ1IjoiYml0Ym94ZXIiLCJhIjoiY2tuazhkcm5nMDZiaDJ2bjA4YzZraTYxbSJ9.VHWcZ-7Q7-zOcBkQ5B0Hzw';

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
  title: string,
  subtitle: string,
  description: string,
  url: string,
  state: string,
  additional_link: string,
  additional_link_name: string
  point: Geometry
  geometry: Geometry
};

const url = new URL(window.location.href);
url.searchParams.get('c');

const map = new mapboxgl.Map({
  container: 'map',
  style: 'mapbox://styles/mapbox/streets-v11',
});

interface MapObject {
  marker?: Marker,
  layerName?: string
  item: GeoItem
}

const mapObjects: {
  [key: number] : MapObject
} = {};

const isLineString = (item: Geometry) => {
  const collectionType = uniq(item.geometries?.map((geometry) => geometry.type));
  return item.type === 'LineString' || isEqual(collectionType, ['LineString']);
};

const popupForItem = (item: GeoItem):Popup => new mapboxgl.Popup({ className: 'my-popup', offset: 25 }).setText(
  item.title,
);

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

const addMarkerForPoint = (item: GeoItem) => {
  const marker = new mapboxgl.Marker()
    .setPopup(popupForItem(item))
    .setLngLat(item.point.coordinates as LngLatLike)
    .addTo(map);

  marker.getElement().addEventListener('click', (event) => {
    event.preventDefault();
  });
  return marker;
};

const addLayerForGeometry = (layerName:string, item:GeoItem) => {
  map.addSource(layerName, {
    type: 'geojson',
    data: item.geometry as any,
  });

  if (isLineString(item.geometry)) {
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

const updateMapItems = () => {
  const mapItems = JSON.parse(document.getElementById('map-data')?.innerHTML || '{}')?.items;
  const mapIds:number[] = mapItems.map((item:GeoItem) => item.id);

  removeUneededMapItems(mapIds);

  mapItems.forEach((item:GeoItem) => {
    if (!mapObjects[item.id]) {
      const mapItem:MapObject = {
        item,
      };
      mapObjects[item.id] = mapItem;

      if (item.point) {
        mapItem.marker = addMarkerForPoint(item);
      }

      if (item.geometry) {
        const layerName = `map-item-${item.id}`;
        mapItem.layerName = layerName;
        addLayerForGeometry(layerName, item);
      }
    }
  });
};

const InteractiveMap = {
  mounted() {
    const hook = this as unknown as ViewHookInterface;
    const mapElement = document.getElementById('map');

    const position:LngLatLike = [
      parseFloat(mapElement?.getAttribute('data-position-lng') || '0'),
      parseFloat(mapElement?.getAttribute('data-position-lat') || '0'),
    ];
    map.setCenter(position);
    map.setZoom(parseInt(mapElement?.getAttribute('data-position-zoom') || '10', 10));

    map.setPadding({
      right: 42 * 16,
      top: 0,
      left: 0,
      bottom: 0,
    });

    map.on('zoomend', () => {
      hook.pushEvent('updateZoom', { zoom: map.getZoom() });
    });
    map.on('moveend', () => {
      hook.pushEvent('updateCoordinates', map.getCenter());
    });

    map.on('click', (e) => {
      if (!e.originalEvent.defaultPrevented) {
        const layers = map.queryRenderedFeatures(e.point);

        if (layers[0]) {
          const match = layers[0].source.match(/map-item-(\d*)/);
          if (match) {
            const itemId = parseInt(match[1], 10);
            const popup = popupForItem(mapObjects[itemId].item);
            popup.setLngLat(e.lngLat);
            popup.addTo(map);
          }
        }
      }
    });
    updateMapItems();
  },
  updated() {
    updateMapItems();
  },
};

export default InteractiveMap;
