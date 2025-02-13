// dashboard/containers/widget-title.js

import { connect } from 'react-redux';

import * as c from '../constant';
import { setWidgetTitleSel } from '../action';

import WidgetTitle from '../components/widget-title';

const mapStateToProps = (state, ownProps) => {
  return {
    selected: state[c.NAME].widgetTitleSelected[ownProps.selId],
  };
};

export default connect(mapStateToProps, { setWidgetTitleSel })(WidgetTitle);