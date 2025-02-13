import Helmet from 'react-helmet';
import Page from '../../hocs/securedPage';
import Iframe from '../../components/iframe';

export default Page(() => (
  <div>
    <Helmet>
      <title>Top Hosts</title>
    </Helmet>
    <Iframe src={`https://${window.cluster[window.env.CLUSTER].CUBE_URL}/grafana/d/M3ncw6lmk/top-hosts?refresh=5m&kiosk=tv&orgId=1`} />
  </div>
));