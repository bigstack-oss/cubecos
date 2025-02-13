// dashboard/components/topten-widget.js

import React from 'react';
import createReactClass from 'create-react-class';

import * as c from '../constant';
import IntlMessages from '../../../components/utility/intlMessages';

import TinyLineChart from './tiny-line-chart';
import { ToptenWidgetDiv, ToptenItemDiv } from './topten-widget-style'

import Link from 'next/link';

const getUrlOld = {
  host: id => `http://${window.cluster[window.env.CLUSTER].CUBE_URL}/grafana/d/i-R2q81iz/host?refresh=5m&kiosk=tv&orgId=1&var-HOST=${id}`,
  vm: id => `http://${window.cluster[window.env.CLUSTER].CUBE_URL}/grafana/d/PVW6vU7Wz/instance?refresh=5m&kiosk=tv&orgId=1&var-UUID=${id}`,
}

const getUrl = {
  host: id => `/monitoring/host?id=${id}`,
  vm: id => `/monitoring/instance?id=${id}`,
}

const UNITS = {
  cpu: '%',
  mem: '%',
  disk: '%',
  diskr: 'B/s',
  diskw: 'B/s',
  netin: 'bps',
  netout: 'bps',
}

const COLORS = {
  cpu: '#8599d6',
  mem: '#85d685',
  disk: '#f5d97f',
  diskr: '#71bdc9',
  diskw: '#c9b671',
  netin: '#c97184',
  netout: '#c471c9',
}

const getStatus = (cat, usage) => {
  switch(cat) {
    case 'cpu':
    case 'mem':
    case 'disk':
      if (usage >= 90)
        return 'critical';
      else if ( usage >= 75 )
        return 'warning';
      break;
    default:
      return '';
  }
};

const prettier = (value, unit) => {
  if (value == null)
    return def;
  if (value > 1000000000 || value < -1000000000)
    return `${parseFloat(value / 1000000000).toFixed(2)} G${unit}`;
  if (value > 1000000 || value < -1000000)
    return `${parseFloat(value / 1000000).toFixed(2)} M${unit}`;
  if (value > 1000 || value < -1000)
    return `${parseFloat(value / 1000).toFixed(2)} K${unit}`;
  if (value > 100 || value < -100)
    return parseInt(value) + ' ' + unit;
  else
    return parseFloat(value).toFixed(2) + ' ' + unit;
}

const ToptenItem = ({ cat, selected, id, name, usage, chart }) => {
  return (
    <Link href={getUrl[cat](id)}>
      <a>
        <ToptenItemDiv>
          <div className='toptenItemGroup'>
            <div className='toptenItemRow'>
              <div className='toptenItemName'>
                <p>{name}</p>
              </div>
              <div className={'toptenItemUsage ' + getStatus(selected, usage)}>
                <p><span className='dot'></span>{prettier(usage, UNITS[selected])}</p>
              </div>
              <div className='toptenItemChart'>
                <div className='chartElement'>
                  <TinyLineChart rawData={chart} color={COLORS[selected]} / >
                </div>
              </div>
                <div className='toptenItemAction'>
                  <i className='ti-angle-right'></i>
                </div>
            </div>
          </div>
        </ToptenItemDiv>
      </a>
    </Link>
  );
}

const ToptenWidget = createReactClass({
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
    const { cat, api, selected, topten, fetchTopten } = this.props;

    if (this.state.refresh) {
        fetchTopten(cat, api, 'cpu');
        fetchTopten(cat, api, 'mem');
        if (cat == 'host')
          fetchTopten(cat, api, 'disk');
        else {
          fetchTopten(cat, api, 'diskr');
          fetchTopten(cat, api, 'diskw');
        }
        fetchTopten(cat, api, 'netin');
        fetchTopten(cat, api, 'netout');
        this.setState({ refresh: false });
    }

    return (
      <ToptenWidgetDiv>
        {topten[selected].map((item) =>
          <ToptenItem key={item.id} cat={cat} selected={selected} {...item} />
        )}
      </ToptenWidgetDiv>
    );
  }
});

export default ToptenWidget;