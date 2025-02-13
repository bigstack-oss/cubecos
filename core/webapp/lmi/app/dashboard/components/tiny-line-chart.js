// dashboard/components/tiny-line-chart.js

import React from 'react';
import { LineChart, Line, ResponsiveContainer, YAxis, Tooltip } from 'recharts';

const DATA_POINT_NUM = 60;

const prettier = (value, def) => {
  if (value == null)
    return def;
  if (value > 1000000000 || value < -1000000000)
    return `${parseFloat(value / 1000000000).toFixed(2)} g`;
  if (value > 1000000 || value < -1000000)
    return `${parseFloat(value / 1000000).toFixed(2)} m`;
  if (value > 1000 || value < -1000)
    return `${parseFloat(value / 1000).toFixed(2)} k`;
  if (value > 100 || value < -100)
    return parseInt(value) + ' ';
  else
    return parseFloat(value).toFixed(2) + ' ';
}

const datePrettier = (value, chartData) => {
  const idx = parseInt(value);
  let d = new Date(chartData[idx].time / 1000000);
  let ap = '';
  let h = d.getHours();
  if (h < 12)
    ap = "AM";
  else {
    h -= 12
    ap = "PM";
  }
  return h + ':' + d.getMinutes() + ' ' + ap;
}

const TinyLineChart = ({ rawData, color, tooltip, unit }) => {
  const chartData = [];
  if (rawData != null) {
    const startIdx = rawData.length > DATA_POINT_NUM ? rawData.length - DATA_POINT_NUM : 0;
    for (var i = startIdx; i < rawData.length; i++) {
      const value = rawData[i][1] != null ? parseFloat(rawData[i][1].toFixed(2)) : 0;
      chartData.push({ time: rawData[i][0], value: value ? value : 0 });
    }
  }
  return (
    <ResponsiveContainer width='99%' height='100%'>
      <LineChart data={chartData}>
        {tooltip && <Tooltip labelFormatter={(name) => datePrettier(name, chartData) } formatter={(value, name, props) => [prettier(value, 0) + unit, null]} /> }
        <YAxis hide={true} domain={[0, dataMax => (unit == '%' ? Math.min(dataMax * 2, 100) : dataMax)]}/>
        <Line type='linear' dataKey='value' stroke={color} fill={color} dot={false} />
      </LineChart>
    </ResponsiveContainer>
  );
}

export default TinyLineChart;