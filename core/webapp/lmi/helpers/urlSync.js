import qs from 'qs';

const parents = {
  ecommerce: ['shop', 'cart', 'checkout', 'card'],
  map: ['googlemap', 'leafletmap'],
  charts: [
    'googleChart',
    'reecharts',
    'reactVis',
    'reactChart2',
    'reactTrend',
    'echart',
  ],
  Forms: [
    'InputField',
    'editor',
    'FormsWithValidation',
    'progress',
    'button',
    'tab',
    'checkbox',
    'radiobox',
    'transfer',
    'autocomplete',
  ],
  uielements: [
    'op_badge',
    'op_card',
    'op_carousel',
    'op_collapse',
    'op_popover',
    'op_tooltip',
    'op_tag',
    'op_timeline',
    'dropdown',
    'pagination',
    'rating',
    'tree',
  ],
  advancedUielements: ['reactDates', 'codeMirror', 'uppy', 'dropzone'],
  feedback: ['alert', 'modal', 'message', 'notification', 'popconfirm', 'spin'],
  table: ['table_ant'],
  pages: [
    '404',
    '500',
    'signin',
    'signup',
    'forgotpassword',
    'resetpassword',
    'invoice',
    'comingSoon',
  ],
};

export function getInitData() {
  const initData = qs.parse(window.location.search.slice(1));
  if (initData.toggle)
    initData.toggle.free_shipping = initData.toggle.free_shipping === 'true'
      ? true
      : undefined;
  return initData;
}
export function setUrl(searchState) {
  const search = searchState
    ? `${window.location.pathname}?${qs.stringify(searchState)}`
    : '';
  window.history.pushState(searchState, null, search);
}

export function getDefaultPath() {
  const getParent = lastRoute => {
    let parent;
    Object.keys(parents).forEach(key => {
      parents[key].forEach(p => {
        if (p === lastRoute) {
          parent = key;
        }
      });
    });
    return parent ? [parent, lastRoute] : [lastRoute];
  };
  return [];
}
