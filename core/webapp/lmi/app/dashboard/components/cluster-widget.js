// dashboard/components/cluster-widget.js

import React from 'react';
import createReactClass from 'create-react-class';

import * as c from '../constant';
import IntlMessages from '../../../components/utility/intlMessages';

import TinyLineChart from './tiny-line-chart';
import { ClusterWidgetDiv } from './cluster-widget-style'

const ClusterWidget = createReactClass({
  getInitialState: function() {
    return { refresh: true };
  },

  componentDidMount: function() {
    this.interval = setInterval(() => this.setState({ refresh: true }), c.SHORT_REFRESH);
  },

  componentWillUnmount: function() {
    clearInterval(this.interval);
  },

  render: function() {
    const { cat, title, api, color, usage, fetchClusterUsage } = this.props;

    if (this.state.refresh) {
      fetchClusterUsage(cat, api);
      this.setState({ refresh: false })
    }

    return (
      <ClusterWidgetDiv className={usage[cat].trend > 0 ? 'up' : 'down' }>
        <div className="clusterWidget">
          <div className="clusterTitle">
            <h2><IntlMessages id={title} /></h2>
            <p>{usage[cat].total.toFixed(2)}%</p>
          </div>
          <div className="clusterBlock">
            <div className="clusterChart">
              <div className="chartElement">
                <TinyLineChart rawData={usage[cat].chart} color={color} tooltip={true} unit='%' />
              </div>
            </div>
            <div className="clusterSubtitle">
              <h5><IntlMessages id={'widget.cluster.usage24h'} /></h5>
              <p className="clusterSubText">
                <span className={usage[cat].trend > 0 ? 'ti-stats-up' : 'ti-stats-down'} />
                {usage[cat].trend.toFixed(2)}%
              </p>
            </div>
          </div>
        </div>
      </ClusterWidgetDiv>
    );
  }
});

export default ClusterWidget;
