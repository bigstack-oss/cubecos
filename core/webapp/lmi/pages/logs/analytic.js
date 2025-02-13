import Helmet from 'react-helmet';
import Page from '../../hocs/securedPage';
import Iframe from '../../components/iframe';

export default Page(({url}) => (
  <div>
    <Helmet>
      <title>Host</title>
    </Helmet>
    <Iframe src={`https://${window.cluster[window.env.CLUSTER].CUBE_URL}/opensearch-dashboards/app/discover#/view/7f32d630-0275-11ec-8ec6-0d4cf465bb19`} />
  </div>
));
