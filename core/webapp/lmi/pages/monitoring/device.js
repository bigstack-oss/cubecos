import Helmet from 'react-helmet';
import Page from '../../hocs/securedPage';
import Iframe from '../../components/iframe';

export default Page(({url}) => (
  <div>
    <Helmet>
      <title>Device</title>
    </Helmet>
    { url.query.id
      ? <Iframe src={`https://${window.cluster[window.env.CLUSTER].CUBE_URL}/grafana/d/i-device/device?refresh=5m&kiosk=tv&orgId=1&var-HOST=${url.query.id}`} />
      : <Iframe src={`https://${window.cluster[window.env.CLUSTER].CUBE_URL}/grafana/d/i-device/device?refresh=5m&orgId=1`} />
    }
  </div>
));