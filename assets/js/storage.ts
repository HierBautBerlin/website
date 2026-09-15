// Remembers things in the browser. localStorage can be missing or throw
// (private windows, blocked site data), then nothing is remembered.

const WELCOME_SEEN_KEY = 'hierbautberlin:welcome-seen';
const MAP_POSITION_KEY = 'hierbautberlin:map-position';

export type MapPosition = { lat: number, lng: number, zoom: number };

// Berlin and surroundings, same as in MapLive. Anything else (e.g. 0/0) is a bug.
const inArea = (position: MapPosition) => position.lat >= 52 && position.lat <= 53
  && position.lng >= 12.5 && position.lng <= 14.5;

const read = (key: string): string | null => {
  try {
    return window.localStorage.getItem(key);
  } catch {
    return null;
  }
};

const write = (key: string, value: string) => {
  try {
    window.localStorage.setItem(key, value);
  } catch {
    // not available, nothing to remember
  }
};

export const welcomeSeen = (): boolean => read(WELCOME_SEEN_KEY) === 'true';

export const markWelcomeSeen = () => write(WELCOME_SEEN_KEY, 'true');

export const storedMapPosition = (): MapPosition | null => {
  try {
    const position = JSON.parse(read(MAP_POSITION_KEY) || 'null');
    const valid = position
      && [position.lat, position.lng, position.zoom].every((value) => Number.isFinite(value))
      && inArea(position);
    return valid ? { lat: position.lat, lng: position.lng, zoom: position.zoom } : null;
  } catch {
    return null;
  }
};

export const storeMapPosition = (position: MapPosition) => {
  if (inArea(position)) write(MAP_POSITION_KEY, JSON.stringify(position));
};
