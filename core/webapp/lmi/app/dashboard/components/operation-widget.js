// dashboard/components/operation-widget.js

import React from 'react';
import { Row, Col } from 'antd';
import { PieChart, Pie, Cell, Sector } from 'recharts';
import createReactClass from 'create-react-class';

// import custom styles
import basicStyle from '../../../config/basicStyle';

import * as c from '../constant';
import IntlMessages from '../../../components/utility/intlMessages';

import { OperationsWidgetDiv, OperationsItemDiv } from './operation-widget-style'

const { rowStyle, colStyle } = basicStyle;

const COLORS = {
  cpu: [ '#DDDDDD', '#FFBB28', '#ff5a28' ],
  mem: [ '#DDDDDD', '#00C49F', '#007d65'  ],
  storage: [ '#DDDDDD', '#0088FE', 'f02559e' ],
}

const renderActiveShape = (props) => {
  const RADIAN = Math.PI / 180;
  const { cx, cy, midAngle, innerRadius, outerRadius, startAngle, endAngle,
    fill, payload } = props;
  const cos = Math.cos(-RADIAN * midAngle);
  const textAnchor = cos >= 0 ? 'start' : 'end';
  return (
    <g>
      <text x={cx} y={cy} dy={0} textAnchor='middle' className='piePercent' >
        {payload.orig}%
      </text>
      <text x={cx} y={cy} dy={18} textAnchor='middle' className='pieTotal' fill='#C1C3C7' >
        {payload.total} {payload.unit}
      </text>
      {payload.overused &&
        <text x={cx} y={cy} dy={33} textAnchor='middle' className='pieTotal' fill='#d10252' >
          overused
        </text>
      }
      <Sector
        cx={cx}
        cy={cy}
        innerRadius={innerRadius}
        outerRadius={outerRadius}
        startAngle={startAngle}
        endAngle={endAngle}
        fill={fill}
      />
    </g>
  );
};

const VictoryPieChart = ({ cat, data, overused }) => {
  return (
    <PieChart width={342} height={175}>
      <Pie
        dataKey='value'
        activeIndex={1}
        activeShape={renderActiveShape}
        data={data}
        innerRadius={60}
        outerRadius={80}
        startAngle={90}
        endAngle={-270}
      >
        {data.map((entry, index) =>
          <Cell key={index} fill={ COLORS[cat][index % COLORS[cat].length + overused ] } />
        )}
      </Pie>
     </PieChart>
  );
}

const OperationsItem = ({ cat, label, unit, total, used, pcnt }) => {
  const overused = pcnt > 100 ? 1 : 0;
  const data = [
    { name: 'free', orig: 100 - pcnt, value: 100 - (pcnt % 100), total, unit, overused },
    { name: 'used', orig: pcnt, value: pcnt % 100, total, unit, overused },
  ];

  return (
    <OperationsItemDiv>
      <div className='opsItemTitle'>
        <h2><IntlMessages id={label} /></h2>
      </div>
      <div className='opsItemPie'>
        <VictoryPieChart cat={cat} unit={unit} total={total} used={used} data={data} overused={overused} />
      </div>
      <div className='opsItemDetails'>
        <h4>
          <span>Total</span>
          <p>{total} {unit}</p>
        </h4>
        <h4>
          <span>Used</span>
          <p>{used} {unit}</p>
        </h4>
      </div>
    </OperationsItemDiv>
  );
}

const OperationWidget = createReactClass({
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
    const { summary, fetchOpSummary } = this.props;

    if (this.state.refresh) {
        fetchOpSummary();
        this.setState({ refresh: false });
    }

    const c = summary.cpu;
    const m = summary.mem;
    const s = summary.storage;
    return (
      <OperationsWidgetDiv>
        <div className='opsItem'>
          <Row style={rowStyle} gutter={0} justify='start'>
            <Col lg={8} md={8} sm={24} xs={24} style={colStyle}>
              <OperationsItem
                cat='cpu'
                label='widget.operation.cpu'
                unit='vCPU'
                total={c.total > 0 ? c.total : 0}
                used={c.total > 0 ? c.used : 0}
                pcnt={c.total > 0 ? Math.round(c.used / c.total * 100) : 0}
              />
            </Col>
            <Col lg={8} md={8} sm={24} xs={24} style={colStyle}>
              <OperationsItem
                cat='mem'
                label='widget.operation.memory'
                unit='GB'
                total={m.total > 0 ? parseFloat(m.total / 1024).toFixed(1) : 0}
                used={m.total > 0 ? parseFloat(m.used / 1024).toFixed(1) : 0}
                pcnt={m.total > 0 ? Math.round(m.used / m.total * 100) : 0}
              />
            </Col>
            <Col lg={8} md={8} sm={24} xs={24} style={colStyle}>
              <OperationsItem
                cat='storage'
                label='widget.operation.storage'
                unit='GB'
                total={s.total > 0 ? parseFloat(s.total / 1024 / 1024 / 1024).toFixed(1) : 0}
                used={s.total > 0 ? parseFloat(s.used / 1024 / 1024 / 1024).toFixed(1) : 0}
                pcnt={s.total > 0 ? Math.round(s.used / s.total * 100) : 0}
              />
            </Col>
          </Row>
        </div>
      </OperationsWidgetDiv>
    );
  }
});

export default OperationWidget;