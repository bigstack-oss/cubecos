import Helmet from 'react-helmet';
import Page from '../../hocs/securedPage';
import Iframe from '../../components/iframe';

export default Page(({url}) => (
  <div>
    <Helmet>
      <title>Instance</title>
    </Helmet>
    { url.query.id
      ? <Iframe src={`https://${window.cluster[window.env.CLUSTER].CUBE_URL}/grafana/d/PVW6vU7Wz/instance?refresh=5m&kiosk=tv&orgId=1&var-UUID=${url.query.id}`} />
      : url.query.tid
        ? <Iframe src={`https://${window.cluster[window.env.CLUSTER].CUBE_URL}/grafana/d/PVW6vU7Wz/instance?refresh=5m&orgId=1&var-TID=${url.query.tid}`} />
        : <Iframe src={`https://${window.cluster[window.env.CLUSTER].CUBE_URL}/grafana/d/PVW6vU7Wz/instance?refresh=5m&orgId=1`} />
    }
  </div>
));