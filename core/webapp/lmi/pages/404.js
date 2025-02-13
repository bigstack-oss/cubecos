import Helmet from 'react-helmet';
import Page from '../hocs/defaultPage';
import FourZeroFour from '../containers/Page/404.js';

export default Page(() => (
  <div>
    <Helmet>
      <title>404</title>
    </Helmet>
    <div>
      <FourZeroFour />
    </div>
  </div>
));
