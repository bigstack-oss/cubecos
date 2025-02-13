import Helmet from 'react-helmet';
import Page from '../../hocs/securedPage';
import Iframe from '../../components/iframe';

export default Page(() => (
  <div>
    <Helmet>
      <title>Storage</title>
    </Helmet>
    <Iframe src={`https://${window.cluster[window.env.CLUSTER].CUBE_URL}/grafana/d/QTc_sAxiw/storage?refresh=5m&kiosk=tv&orgId=1`} />
  </div>
));