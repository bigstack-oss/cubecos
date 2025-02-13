const basicData = {
  labels: [
    '12am-3am',
    '3am-6am',
    '6am-9am',
    '9am-12pm',
    '12pm-3pm',
    '3pm-6pm',
    '6pm-9pm',
    '9pm-12am'
  ],

  datasets: [
    {
      title: 'Some Data',
      color: 'light-blue',
      values: [25, 40, 30, 35, 8, 52, 17, -4]
    },
    {
      title: 'Another Set',
      color: 'violet',
      values: [25, 50, -10, 15, 18, 32, 27, 14]
    },
    {
      title: 'Yet Another',
      color: 'blue',
      values: [15, 20, -3, -15, 58, 12, -17, 37]
    }
  ]
};

const heatMapData = {};
const currentDate = new Date();
const heatMapStart = new Date(new Date().setMonth(1, 1));
let timestamp = currentDate.getTime() / 1000;
timestamp = Math.floor(timestamp - timestamp % 86400).toFixed(1); // convert to midnight
for (let i = 0; i < 375; i++) {
  heatMapData[timestamp] = Math.floor(Math.random() * 6) + 1;
  timestamp = Math.floor(timestamp - 86400).toFixed(1);
}

const basicConfig = {
  height: 250,
  format_tooltip_x: d => (d + '').toUpperCase(),
  format_tooltip_y: d => d + ' pts'
};
const barChart = {
  header: 'Bar Chart',
  title: '',
  parent: '#frappeBarChart',
  parentId: 'frappeBarChart',
  type: 'bar',
  data: basicData,
  ...basicConfig
};
const lineChart = {
  header: 'Line Chart',
  title: '',
  parent: '#frappeLineChart',
  parentId: 'frappeLineChart',
  type: 'line',
  data: basicData,
  show_dots: 0,
  heatline: 1,
  region_fill: 1,
  ...basicConfig
};

const scatterChart = {
  header: 'Scatter Chart',
  title: '',
  parent: '#frappeScatterChart',
  parentId: 'frappeScatterChart',
  type: 'scatter',
  data: basicData,
  ...basicConfig
};

const pieChart = {
  header: 'Pie Chart',
  title: '',
  parent: '#frappePieChart',
  parentId: 'frappePieChart',
  type: 'pie',
  data: basicData,
  ...basicConfig
};

const percentageChart = {
  header: 'Percentage Chart',
  title: '',
  parent: '#frappePercentageChart',
  parentId: 'frappePercentageChart',
  type: 'percentage',
  data: basicData,
  ...basicConfig
};
const heatMap = {
  header: 'Heatmap Chart',
  title: '',
  parent: '#heatmap',
  parentId: 'heatmap',
  type: 'heatmap',
  height: 115,
  data: heatMapData, //heatMapData,
  discrete_domains: 1, // default: 0
  start: heatMapStart
};

const heatMapHalloween = {
  header: 'Heatmap Chart Halloween',
  title: '',
  parent: '#heatmapHalloween',
  parentId: 'heatmapHalloween',
  type: 'heatmap',
  height: 115,
  data: heatMapData, //heatMapData,
  discrete_domains: 1, // default: 0
  start: heatMapStart,
  legend_colors: ['#ebedf0', '#fdf436', '#ffc700', '#ff9100', '#06001c']
};

const updatedChart = {
  header: 'Updateable Chart',
  title: '',
  parent: '#frappeupdatedChart',
  parentId: 'frappeupdatedChart',
  data: basicData,
  type: 'line',
  show_dots: 0,
  heatline: 1
};

export {
  barChart,
  lineChart,
  scatterChart,
  pieChart,
  percentageChart,
  heatMap,
  heatMapHalloween,
  updatedChart,
  basicData
};
