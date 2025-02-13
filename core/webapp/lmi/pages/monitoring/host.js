import Helmet from 'react-helmet';
import Page from '../../hocs/securedPage';
import Iframe from '../../components/iframe';

export default Page(({url}) => (
  <div>
    <Helmet>
      <title>Host</title>
    </Helmet>
    { url.query.id
      ? <Iframe src={`https://${window.cluster[window.env.CLUSTER].CUBE_URL}/grafana/d/i-R2q81iz/host?refresh=5m&kiosk=tv&orgId=1&var-HOST=${url.query.id}`} />
      : <Iframe src={`https://${window.cluster[window.env.CLUSTER].CUBE_URL}/grafana/d/i-R2q81iz/host?refresh=5m&orgId=1`} />
    }
  </div>
));