import Helmet from 'react-helmet';
import Page from '../../hocs/securedPage';
import Iframe from '../../components/iframe';

export default Page(({url}) => (
  <div>
    <Helmet>
      <title>Top Instances</title>
    </Helmet>
    { url.query.tid
      ? <Iframe src={`https://${window.cluster[window.env.CLUSTER].CUBE_URL}/grafana/d/qzfq087Wk/top-instances?refresh=5m&kiosk=tv&orgId=1&var-TID=${url.query.tid}`} />
      : <Iframe src={`https://${window.cluster[window.env.CLUSTER].CUBE_URL}/grafana/d/qzfq087Wk/top-instances?refresh=5m&orgId=1`} />
    }
  </div>
));