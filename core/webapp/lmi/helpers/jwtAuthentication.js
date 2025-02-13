import { jwtConfig } from '../config';
import jwtDecode from 'jwt-decode';

class JwtAuth {
  login = async userInfo => {
    if (!userInfo.username || !userInfo.password) {
      return { error: 'please fill in the input' };
    }
    return await fetch(jwtConfig.fetchUrl, {
      method: 'post',
      headers: {
        Accept: 'application/json',
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(userInfo)
    })
      .then(response => response.json())
      .then(res => {
        const result = {};
        if (res.token) {
          result.profile = jwtDecode(res.token);
          result.token = res.token;
          return result;
        } else {
          return res;
        }
      })
      .catch(error => ({ error }));
  };
}
export default new JwtAuth();
