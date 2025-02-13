// dashboard/components/infra-widget.js

import React from 'react';
import { BarChart , Bar , ResponsiveContainer, XAxis, YAxis } from 'recharts';
import createReactClass from 'create-react-class';

import * as c from '../constant';
import IntlMessages from '../../../components/utility/intlMessages';

import { InfraWidgetDiv, InfraItemWidgetDiv } from './infra-widget-style'

const COLORS = {
  control: '#3FB8AF',
  compute: '#DAD8A7',
  storage: '#FF9E9D',
  running: '#555E7B',
  stopped: '#B7D968',
  suspended: '#B576AD',
  paused: '#FDE47F',
  error: '#E04644',
}

const StackedBarChart = ({ name, rawData }) => {
  let chartData = [];
  chartData[0] = rawData;
  return (
    <ResponsiveContainer>
      <BarChart layout="vertical" data={chartData} stackOffset="expand">
          <XAxis hide type="number"/>
          <YAxis hide type="category" />
          {Object.keys(rawData).map((key, i)=>
            <Bar key={i} dataKey={key} fill={COLORS[key]} stackId="a" />
          )}
      </BarChart>
    </ResponsiveContainer>
  );
}

const InfraItem = ({ name, label, unit, data }) => {
  return (
    <InfraItemWidgetDiv>
      <div className='infraItemTitle'>
        <p><IntlMessages id={label} /></p>
        <h5>{data.total}<span><IntlMessages id={unit} /></span></h5>
      </div>
      <div className='infraItemBar'>
        <div className="chartElement">
          <StackedBarChart name={name} rawData={data.summary} />
        </div>
      </div>
      <div className='infraItemDetails'>
        {Object.keys(data.summary).map((key)=>
          <p key={key} className={key} ><span className='dot' />{data.summary[key]} <span className='label'>{key}</span></p>
        )}
      </div>
    </InfraItemWidgetDiv>
  );
}

const InfraWidget = createReactClass({
  getInitialState: function() {
    return { refresh: true };
  },

  componentDidMount: function() {
    this.interval = setInterval(() => this.setState({ refresh: true }), c.LONG_REFRESH);
  },

  componentWillUnmount: function() {
    clearInterval(this.interval);
  },

  render: function() {
    const { summary, fetchInfraSummary } = this.props;

    if (this.state.refresh) {
        fetchInfraSummary();
        this.setState({ refresh: false });
    }

    const role = summary.role;
    const vm = summary.vm;
    return (
      <InfraWidgetDiv>
        <div className='infraSingle'>
          <InfraItem name='Role' label={'widget.infra.role.title'} unit={'widget.infra.role.unit'} data={role} />
          <InfraItem name='VM' label={'widget.infra.vm.title'} unit={'widget.infra.vm.unit'} data={vm} />
        </div>
      </InfraWidgetDiv>
    );
  }
});

export default InfraWidget;