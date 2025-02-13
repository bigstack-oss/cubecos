// dashboard/containers/topten-widget.js

import { connect } from 'react-redux';

import * as c from '../constant';
import { fetchTopten } from '../action';

import ToptenWidget from '../components/topten-widget';

const mapStateToProps = (state, ownProps) => {
  return {
    selected: state[c.NAME].widgetTitleSelected[ownProps.cat],
    topten: state[c.NAME].topten[ownProps.cat],
  };
};

export default connect(mapStateToProps, { fetchTopten })(ToptenWidget);