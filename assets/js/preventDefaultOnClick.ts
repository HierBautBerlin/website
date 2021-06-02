import { ViewHook } from 'phoenix_live_view';

const PreventDefaultOnClick = {
  mounted() {
    const hook = this as unknown as ViewHook;
    hook.el.addEventListener('click', (e) => {
      e.preventDefault();
    });
  },
};

export default PreventDefaultOnClick;
