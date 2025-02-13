import Helmet from 'react-helmet';
import Page from '../../hocs/securedPage';
import Iframe from '../../components/iframe';

export default Page(() => (
  <div>
    <Helmet>
      <title>Top Devices</title>
    </Helmet>
    <Iframe src={`https://${window.cluster[window.env.CLUSTER].CUBE_URL}/grafana/d/topdevices/top-devices?refresh=5m&kiosk=tv&orgId=1`} />
  </div>
));