import { getCookie } from './session';

const jwt = getCookie('id_token');

const customHeader = new Headers({
  Authorization: jwt ? `Bearer ${jwt}` : null,
  Accept: 'application/json',
  'Content-Type': 'application/json',
  'X-Requested-With': 'XMLHttpRequest',
});

const base = (method, url, data = {}) => fetch(url, {
  method,
  headers: customHeader,
  data: Object.keys(data).length ? JSON.stringify(data) : {},
});

const SuperFetch = {};
['get', 'post', 'put', 'delete'].forEach(method => {
  SuperFetch[method] = base.bind(null, method);
});
export default SuperFetch;
