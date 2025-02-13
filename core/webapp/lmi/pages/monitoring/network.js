import Helmet from 'react-helmet';
import Page from '../../hocs/securedPage';
import Iframe from '../../components/iframe';

export default Page(() => (
  <div>
    <Helmet>
      <title>Network</title>
    </Helmet>
    <Iframe src={`https://${window.cluster[window.env.CLUSTER].CUBE_URL}/grafana/d/Xx2kkftWk/network?refresh=5m&kiosk=tv&orgId=1`} />
  </div>
));