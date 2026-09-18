// Remembers things in the browser. localStorage can be missing or throw
// (private windows, blocked site data), then nothing is remembered.

const WELCOME_SEEN_KEY = 'hierbautberlin:welcome-seen';
const MAP_POSITION_KEY = 'hierbautberlin:map-position';
const LIST_FILTERS_KEY = 'hierbautberlin:list-filters';

export type MapPosition = { lat: number, lng: number, zoom: number };

// The filters of the list toolbar, the keys are the ones MapLive expects
export type ListFilters = { hidden_sources: number[], show_old: boolean };

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

// null when nothing was remembered, MapLive then shows every source and
// the old entries
export const storedListFilters = (): ListFilters | null => {
  try {
    const filters = JSON.parse(read(LIST_FILTERS_KEY) || 'null');
    if (!filters || typeof filters !== 'object') return null;

    const sources: unknown[] = Array.isArray(filters.hidden_sources) ? filters.hidden_sources : [];
    return {
      hidden_sources: sources.filter((id): id is number => Number.isInteger(id)),
      show_old: filters.show_old !== false,
    };
  } catch {
    return null;
  }
};

export const storeListFilters = (filters: ListFilters) => {
  write(LIST_FILTERS_KEY, JSON.stringify(filters));
};
