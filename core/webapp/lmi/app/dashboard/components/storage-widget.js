// dashboard/components/storage-widget.js

import React from 'react';
import createReactClass from 'create-react-class';

import * as c from '../constant';
import IntlMessages from '../../../components/utility/intlMessages';
import { injectIntl } from 'react-intl';

import TinyLineChart from './tiny-line-chart';
import { StorageTabDiv, StorageItemDiv } from './storage-widget-style'

const prettier = (value, def) => {
  if (value == null)
    return def;
  if (value > 1000000000 || value < -1000000000)
    return `${parseFloat(value / 1000000000).toFixed(2)}g`;
  if (value > 1000000 || value < -1000000)
    return `${parseFloat(value / 1000000).toFixed(2)}m`;
  if (value > 1000 || value < -1000)
    return `${parseFloat(value / 1000).toFixed(2)}k`;
  if (value > 100 || value < -100)
    return parseInt(value);
  else
    return parseFloat(value).toFixed(2);
}

const StorageWidget = createReactClass({
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
    const {
      intl, cat, api, icon, title, color, chartColor,
      usage, unit, fetchStorageUsage
    } = this.props;

    if (this.state.refresh) {
      fetchStorageUsage(cat, api);
      this.setState({ refresh: false })
    }

    const read = usage[cat].read;
    const write = usage[cat].write;

    return (
      <StorageTabDiv>
        <div className={'storageTab ' + color}>
          <div className={'storageTabIcon ' + icon}></div>
          <div className='storageTrend'>
            <p>
              <span className={read.trend > 0 ? 'ti-stats-up' : 'ti-stats-down'} />
              {prettier(read.trend, 0)}
            </p>
            <p>
              <span className={write.trend > 0 ? 'ti-stats-up' : 'ti-stats-down'} />
              {prettier(write.trend, 0)}
            </p>
          </div>
        </div>
        <div className='storageWidget'>
          <h2><IntlMessages id={title} /></h2>
          <StorageItemDiv>
            <div className='storageItemChart'>
              <div className='chartElement'>
                <TinyLineChart rawData={read.chart} color={chartColor} tooltip={true} unit={intl.formatMessage({id: unit})} />
              </div>
            </div>
            <div className='storageItemTotal'>
              <p><IntlMessages id={'widget.stroage.title.read'} /></p>
              <h2>{prettier(read.rate, 0)}</h2>
              <p><IntlMessages id={unit} /></p>
            </div>
          </StorageItemDiv>
          <StorageItemDiv>
            <div className='storageItemChart'>
              <div className='chartElement'>
                <TinyLineChart rawData={write.chart} color={chartColor} tooltip={true} unit={intl.formatMessage({id: unit})} />
              </div>
            </div>
            <div className='storageItemTotal'>
              <p><IntlMessages id={'widget.stroage.title.write'} /></p>
              <h2>{prettier(write.rate, 0)}</h2>
              <p><IntlMessages id={unit} /></p>
            </div>
          </StorageItemDiv>
        </div>
      </StorageTabDiv>
    );
  }
});

export default injectIntl(StorageWidget);