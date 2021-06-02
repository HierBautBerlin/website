import { ViewHookInterface } from 'phoenix_live_view';

const PreventDefaultOnClick = {
  mounted() {
    const hook = this as unknown as ViewHookInterface;
    hook.el.addEventListener('click', (e) => {
      e.preventDefault();
    });
  },
};

export default PreventDefaultOnClick;
