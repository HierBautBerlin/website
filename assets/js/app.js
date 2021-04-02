// We need to import the CSS so that webpack will load it.
// The MiniCssExtractPlugin is used to separate it out into
// its own CSS file.
import '../css/app.scss';

import 'phoenix_html';
import { Socket } from 'phoenix';
import topbar from 'topbar';
import { LiveSocket } from 'phoenix_live_view';
import InteractiveMap from './interactiveMap';

const Hooks = {
  InteractiveMap,
};

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute('content');
const liveSocket = new LiveSocket('/live', Socket, { hooks: Hooks, params: { _csrf_token: csrfToken } });

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: '#29d' }, shadowColor: 'rgba(0, 0, 0, .3)' });
window.addEventListener('phx:page-loading-start', (_info) => topbar.show());
window.addEventListener('phx:page-loading-stop', (_info) => topbar.hide());

liveSocket.connect();

window.liveSocket = liveSocket;
