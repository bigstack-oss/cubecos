import echarts from 'echarts';
import { largeDataGraph, largeDataLunar } from './largeData';

function getVirtulData(year) {
  year = year || '2017';
  const date = +echarts.number.parseDate(year + '-01-01');
  const end = +echarts.number.parseDate(+year + 1 + '-01-01');
  const dayTime = 3600 * 24 * 1000;
  const data = [];
  for (let time = date; time < end; time += dayTime) {
    data.push([
      echarts.format.formatTime('yyyy-MM-dd', time),
      Math.floor(Math.random() * 1000),
    ]);
  }
  return data;
}
function randomData() {
  return Math.round(Math.random() * 1000);
}

function SimpleChart() {
  const option = {
    title: {
      text: 'Simple Chart',
    },
    tooltip: {
      trigger: 'axis',
    },
    legend: {
      data: ['Series 1', 'Series 2', 'Series 3'],
    },
    toolbox: {
      feature: {
        saveAsImage: {
          title: 'Download',
        },
      },
    },
    color: ['#f09875', '#c64187', '#795cae'],
    grid: {
      left: '3%',
      right: '4%',
      bottom: '3%',
      containLabel: true,
    },
    xAxis: [
      {
        type: 'category',
        boundaryGap: false,
        data: [
          'Monday ',
          'Tuesday ',
          'Wednesday ',
          'Thursday ',
          'Friday ',
          'Saturday ',
          'Sunday',
        ],
      },
    ],
    yAxis: [
      {
        type: 'value',
      },
    ],
    series: [
      {
        name: 'Series 1',
        type: 'line',
        stack: 'Total',
        areaStyle: { normal: {} },
        data: [120, 132, 101, 134, 90, 230, 210],
      },
      {
        name: 'Series 2',
        type: 'line',
        stack: 'Total',
        areaStyle: { normal: {} },
        data: [220, 182, 191, 234, 290, 330, 310],
      },
      {
        name: 'Series 3',
        type: 'line',
        stack: 'Total',
        areaStyle: { normal: {} },
        data: [150, 232, 201, 154, 190, 330, 410],
      },
    ],
  };
  return option;
}
function ChartWithEventComponent() {
  const option = {
    title: {
      text: '',
      subtext: '',
      // text: 'Chart With Event',
      // subtext: 'Purely Fractional',
      x: 'center',
    },
    tooltip: {
      trigger: 'item',
      formatter: '{a} <br/>{b} : {c} ({d}%)',
    },
    legend: {
      orient: 'vertical',
      left: 'left',
      data: [
        'Direct access',
        'mail marketing',
        'affiliate ad',
        'video ad',
        'search engine',
      ],
    },
    color: ['#e86e7a', '#c64187', '#795cae', '#a3d1e6', '#f09875'],
    series: [
      {
        name: 'Access source',
        type: 'pie',
        radius: '55%',
        center: ['50%', '60%'],
        data: [
          { value: 335, name: 'Direct access' },
          { value: 310, name: 'mail marketing' },
          { value: 234, name: 'affiliate ad' },
          { value: 135, name: 'video ad' },
          { value: 1548, name: 'search engine' },
        ],
        itemStyle: {
          emphasis: {
            shadowBlur: 10,
            shadowOffsetX: 0,
            shadowColor: 'rgba(0, 0, 0, 0.5)',
          },
        },
      },
    ],
  };
  return option;
}
function ChartShowLoadingComponent() {
  const option = {
    title: {
      // text: 'Chart ShowLoading Component'
      text: '',
    },
    tooltip: {},
    legend: {
      data: ['Allocated Budget', 'Actual Spending'],
    },
    color: ['#ff6384', '#48A6F2'],
    radar: {
      indicator: [
        { name: 'sales', max: 6500 },
        { name: 'Administration', max: 16000 },
        { name: 'Information Techology', max: 30000 },
        { name: 'Customer Support', max: 38000 },
        { name: 'Development', max: 52000 },
        { name: 'Marketing', max: 25000 },
      ],
    },
    series: [
      {
        name: 'Budget vs spending',
        type: 'radar',
        data: [
          {
            value: [4300, 10000, 28000, 35000, 50000, 19000],
            name: 'Allocated Budget',
          },
          {
            value: [5000, 14000, 28000, 31000, 42000, 21000],
            name: 'Actual Spending',
          },
        ],
      },
    ],
  };
  return option;
}
function ChartAPIComponent() {
  const option = {
    title: {
      text: '',
      subtext: '',
      // text: 'Chart API',
      // subtext: 'Fake data',
    },
    tooltip: {
      trigger: 'item',
      formatter: '{a} <br/>{b} : {c}%',
    },
    toolbox: {
      feature: {
        dataView: {
          readOnly: false,
          title: 'View',
          lang: ['data view', 'turn off', 'refresh'],
        },
        restore: {
          title: 'Reset',
        },
        saveAsImage: {
          title: 'Download',
        },
      },
    },
    legend: {
      data: ['Show', 'Click on', 'access', 'advisory', 'Order'],
    },
    color: ['#e86e7a', '#c64187', '#795cae', '#a3d1e6', '#f09875'],
    series: [
      {
        name: 'expected',
        type: 'funnel',
        left: '10%',
        width: '80%',
        label: {
          normal: {
            formatter: '{b}expected',
          },
          emphasis: {
            position: 'inside',
            formatter: '{b}expected: {c}%',
          },
        },
        labelLine: {
          normal: {
            show: false,
          },
        },
        itemStyle: {
          normal: {
            opacity: 0.7,
          },
        },
        data: [
          { value: 60, name: 'access' },
          { value: 40, name: 'advisory' },
          { value: 20, name: 'Order' },
          { value: 80, name: 'Click on' },
          { value: 100, name: 'Show' },
        ],
      },
      {
        name: 'actual',
        type: 'funnel',
        left: '10%',
        width: '80%',
        maxSize: '80%',
        label: {
          normal: {
            position: 'inside',
            formatter: '{c}%',
            textStyle: {
              color: '#fff',
            },
          },
          emphasis: {
            position: 'inside',
            formatter: '{b}actual: {c}%',
          },
        },
        itemStyle: {
          normal: {
            opacity: 0.5,
            borderColor: '#fff',
            borderWidth: 2,
          },
        },
        data: [
          { value: 30, name: 'access' },
          { value: 10, name: 'advisory' },
          { value: 5, name: 'Order' },
          { value: 50, name: 'Click on' },
          { value: 80, name: 'Show' },
        ],
      },
    ],
  };

  return option;
}
function ThemeChartComponent() {
  const option = {
    title: {
      text: 'Theme Chart',
      subtext: 'From ExcelHome',
    },
    tooltip: {
      trigger: 'axis',
      axisPointer: {
        type: 'shadow',
      },
    },
    legend: {
      data: ['expenditure', 'income'],
    },
    grid: {
      left: '3%',
      right: '4%',
      bottom: '3%',
      containLabel: true,
    },
    xAxis: {
      type: 'category',
      splitLine: { show: false },
      data: [
        'November 1',
        'November 1',
        'November 3',
        'November 4',
        'November 5',
        'November 6',
        'November 7 ',
        'November 8',
        'November 9',
        'November 10',
        'November 11',
      ],
    },
    yAxis: {
      type: 'value',
    },
    color: ['#ff6384', '#48A6F2'],
    series: [
      {
        name: 'Auxiliary',
        type: 'bar',
        stack: 'Total amount',
        itemStyle: {
          normal: {
            barBorderColor: 'rgba(0,0,0,0)',
            color: 'rgba(0,0,0,0)',
          },
          emphasis: {
            barBorderColor: 'rgba(0,0,0,0)',
            color: 'rgba(0,0,0,0)',
          },
        },
        data: [0, 900, 1245, 1530, 1376, 1376, 1511, 1689, 1856, 1495, 1292],
      },
      {
        name: 'income',
        type: 'bar',
        stack: 'Total amount',
        label: {
          normal: {
            show: true,
            position: 'top',
          },
        },
        data: [900, 345, 393, '-', '-', 135, 178, 286, '-', '-', '-'],
      },
      {
        name: 'expenditure',
        type: 'bar',
        stack: 'Total amount',
        label: {
          normal: {
            show: true,
            position: 'bottom',
          },
        },
        data: ['-', '-', '-', 108, 154, '-', '-', '-', 119, 361, 203],
      },
    ],
  };
  return option;
}
function MapChartComponent() {
  const option = {
    title: {
      text: 'Iphone sales',
      subtext: 'Purely fictional',
      left: 'center',
    },
    tooltip: {
      trigger: 'item',
    },
    legend: {
      orient: 'vertical',
      left: 'left',
      data: ['iphone3', 'iphone4', 'iphone5'],
    },
    visualMap: {
      min: 0,
      max: 2500,
      left: 'left',
      top: 'bottom',
      text: ['High', 'low'],
      calculable: true,
    },
    toolbox: {
      show: true,
      orient: 'vertical',
      left: 'right',
      top: 'center',
      feature: {
        dataView: {
          readOnly: false,
          title: 'View',
          lang: ['data view', 'turn off', 'refresh'],
        },
        restore: {
          title: 'Reset',
        },
        saveAsImage: {
          title: 'Download',
        },
      },
    },
    color: ['#511E78', '#ff6384', '#48A6F2'],
    series: [
      {
        name: 'iphone3',
        type: 'map',
        mapType: 'china',
        roam: false,
        label: {
          normal: {
            show: true,
          },
          emphasis: {
            show: true,
          },
        },
        data: [
          { Name: 'Beijing', value: randomData() },
          { Name: 'Tianjin', value: randomData() },
          { Name: 'Shanghai', value: randomData() },
          { Name: 'Chongqing', value: randomData() },
          { Name: 'Hebei', value: randomData() },
          { Name: 'Henan', value: randomData() },
          { Name: 'Yunnan', value: randomData() },
          { Name: 'Liaoning', value: randomData() },
          { Name: 'Heilongjiang', value: randomData() },
          { Name: 'Hunan', value: randomData() },
          { Name: 'Anhui', value: randomData() },
          { Name: 'Shandong', value: randomData() },
          { Name: 'Xinjiang', value: randomData() },
          { Name: 'Jiangsu', value: randomData() },
          { Name: 'Zhejiang', value: randomData() },
          { Name: 'Jiangxi', value: randomData() },
          { Name: 'Hubei', value: randomData() },
          { Name: 'Guangxi', value: randomData() },
          { Name: 'Gansu', value: randomData() },
          { Name: 'Shanxi', value: randomData() },
          { Name: 'Inner Mongolia', value: randomData() },
          { Name: 'Shaanxi', value: randomData() },
          { Name: 'Jilin', value: randomData() },
          { Name: 'Fujian', value: randomData() },
          { Name: 'Guizhou', value: randomData() },
          { Name: 'Guangdong', value: randomData() },
          { Name: 'Qinghai', value: randomData() },
          { Name: 'Tibet', value: randomData() },
          { Name: 'Sichuan', value: randomData() },
          { Name: 'Ningxia', value: randomData() },
          { Name: 'Hainan', value: randomData() },
          { Name: 'Taiwan', value: randomData() },
          { Name: 'Hong Kong', value: randomData() },
          { Name: 'Macau', value: randomData() },
        ],
      },
      {
        name: 'iphone4',
        type: 'map',
        mapType: 'china',
        label: {
          normal: {
            show: true,
          },
          emphasis: {
            show: true,
          },
        },
        data: [
          { Name: 'Beijing', value: randomData() },
          { Name: 'tenez', value: randomData() },
          { Name: 'Shanghai', value: randomData() },
          { Name: 'Chongqing', value: randomData() },
          { Name: 'Hebei', value: randomData() },
          { Name: 'Anhui', value: randomData() },
          { Name: 'Xinjiang', value: randomData() },
          { Name: 'Zhejiang', value: randomData() },
          { Name: 'Jiangxi', value: randomData() },
          { Name: 'Shanxi', value: randomData() },
          { Name: 'Inner Mongolia', value: randomData() },
          { Name: 'Jilin', value: randomData() },
          { Name: 'Fujian', value: randomData() },
          { Name: 'Guangdong', value: randomData() },
          { Name: 'Tibet', value: randomData() },
          { Name: 'Sichuan', value: randomData() },
          { Name: 'Ningxia', value: randomData() },
          { Name: 'Hong Kong', value: randomData() },
          { Name: 'Macau', value: randomData() },
        ],
      },
      {
        name: 'iphone5',
        type: 'map',
        mapType: 'china',
        label: {
          normal: {
            show: true,
          },
          emphasis: {
            show: true,
          },
        },
        data: [
          { Name: 'Beijing', value: randomData() },
          { Name: 'tenez', value: randomData() },
          { Name: 'Shanghai', value: randomData() },
          { Name: 'Guangdong', value: randomData() },
          { Name: 'Taiwan', value: randomData() },
          { Name: 'Hong Kong', value: randomData() },
          { Name: 'Macau', value: randomData() },
        ],
      },
    ],
  };
  return option;
}
function GraphComponent() {
  const webkitDep = largeDataGraph;
  const option = {
    legend: {
      data: ['HTMLElement', 'WebGL', 'SVG', 'CSS', 'Other'],
    },
    color: ['#511E78', '#ff6384', '#00b16a', '#ffbf00', '#48A6F2'],
    series: [
      {
        type: 'graph',
        layout: 'force',
        animation: false,
        label: {
          normal: {
            position: 'right',
            formatter: '{b}',
          },
        },
        draggable: true,
        data: webkitDep.nodes.map((node, idx) => {
          node.id = idx;
          return node;
        }),
        categories: webkitDep.categories,
        force: {
          edgeLength: 5,
          repulsion: 20,
          gravity: 0.2,
        },
        edges: webkitDep.links,
      },
    ],
  };
  return option;
}
function LunarCalendarComponent() {
  let heatmapData = [];
  let lunarData = [];
  for (let i = 0; i < largeDataLunar.length; i++) {
    heatmapData.push([largeDataLunar[i][0], Math.random() * 300]);
    lunarData.push([
      largeDataLunar[i][0],
      1,
      largeDataLunar[i][1],
      largeDataLunar[i][2],
    ]);
  }
  const option = {
    tooltip: {
      formatter: params => {
        return 'Rainfall: ' + params.value[1].toFixed(2);
      },
    },
    visualMap: {
      show: false,
      min: 0,
      max: 300,
      calculable: true,
      seriesIndex: [2],
      orient: 'horizontal',
      left: 'center',
      bottom: 20,
      inRange: {
        color: ['#C8E4FB', '#48A6F2'],
        opacity: 0.3,
      },
      controller: {
        inRange: {
          opacity: 0.5,
        },
      },
    },
    calendar: [
      {
        left: 'center',
        top: 'middle',
        cellSize: [70, 70],
        yearLabel: { show: false },
        orient: 'vertical',
        dayLabel: {
          firstDay: 1,
          nameMap: 'en',
        },
        monthLabel: {
          show: false,
        },
        range: '2017-03',
      },
    ],

    series: [
      {
        type: 'scatter',
        coordinateSystem: 'calendar',
        symbolSize: 1,
        label: {
          normal: {
            show: true,
            formatter: params => {
              const d = echarts.number.parseDate(params.value[0]);
              return d.getDate() + '\n\n' + params.value[2] + '\n\n';
            },
            textStyle: {
              color: '#000',
            },
          },
        },
        data: lunarData,
      },
      {
        type: 'scatter',
        coordinateSystem: 'calendar',
        symbolSize: 1,
        label: {
          normal: {
            show: true,
            formatter: params => {
              return '\n\n\n' + (params.value[3] || '');
            },
            textStyle: {
              fontSize: 14,
              fontWeight: 700,
              color: '#a00',
            },
          },
        },
        data: lunarData,
      },
      {
        name: 'Rainfall',
        type: 'heatmap',
        coordinateSystem: 'calendar',
        data: heatmapData,
      },
    ],
  };
  return option;
}
function LiquidfillComponent() {
  return {
    series: [
      {
        type: 'liquidFill',
        data: [0.45],
      },
    ],
  };
}
function CalendarComponent() {
  const graphData = [
    [1485878400000, 260],
    [1486137600000, 200],
    [1486569600000, 279],
    [1486915200000, 847],
    [1487347200000, 241],
    [1487779200000, 411],
    [1488124800000, 985],
  ];
  const links = graphData.map((item, idx) => {
    return {
      source: idx,
      target: idx + 1,
    };
  });
  links.pop();
  const option = {
    tooltip: {
      position: 'top',
    },
    visualMap: [
      {
        min: 0,
        max: 1000,
        calculable: true,
        seriesIndex: [2, 3, 4],
        orient: 'horizontal',
        color: ['#ff6384', '#ffa1b5'],
        left: '55%',
        bottom: 20,
      },
      {
        min: 0,
        max: 1000,
        inRange: {
          color: ['grey'],
          opacity: [0, 0.3],
        },
        controller: {
          inRange: {
            opacity: [0.3, 0.6],
          },
          outOfRange: {
            color: '#ccc',
          },
        },
        calculable: true,
        seriesIndex: [1],
        orient: 'horizontal',
        left: '10%',
        bottom: 20,
      },
    ],
    calendar: [
      {
        orient: 'vertical',
        yearLabel: {
          margin: 40,
        },
        monthLabel: {
          nameMap: 'en',
          margin: 20,
        },
        dayLabel: {
          firstDay: 1,
          nameMap: 'en',
        },
        cellSize: 40,
        range: '2017-02',
      },
      {
        orient: 'vertical',
        yearLabel: {
          margin: 40,
        },
        monthLabel: {
          margin: 20,
        },
        cellSize: 40,
        left: 460,
        range: '2017-01',
      },
      {
        orient: 'vertical',
        yearLabel: {
          margin: 40,
        },
        monthLabel: {
          margin: 20,
        },
        cellSize: 40,
        top: 350,
        range: '2017-03',
      },
      {
        orient: 'vertical',
        yearLabel: {
          margin: 40,
        },
        dayLabel: {
          firstDay: 1,
          NameMap: [
            'Sunday',
            'Monday',
            'Tuesday',
            'Wednesday',
            'Thursday',
            'Friday',
            'Saturday',
          ],
        },
        monthLabel: {
          nameMap: 'en',
          margin: 20,
        },
        cellSize: 40,
        top: 350,
        left: 460,
        range: '2017-04',
      },
    ],

    series: [
      {
        type: 'graph',
        edgeSymbol: ['none', 'arrow'],
        coordinateSystem: 'calendar',
        links: links,
        symbolSize: 10,
        calendarIndex: 0,
        data: graphData,
      },
      {
        type: 'heatmap',
        coordinateSystem: 'calendar',
        data: getVirtulData(2017),
      },
      {
        type: 'effectScatter',
        coordinateSystem: 'calendar',
        calendarIndex: 1,
        symbolSize: val => {
          return val[1] / 40;
        },
        data: getVirtulData(2017),
      },
      {
        type: 'scatter',
        coordinateSystem: 'calendar',
        calendarIndex: 2,
        symbolSize: val => {
          return val[1] / 60;
        },
        data: getVirtulData(2017),
      },
      {
        type: 'heatmap',
        coordinateSystem: 'calendar',
        calendarIndex: 3,
        data: getVirtulData(2017),
      },
    ],
  };
  return option;
}
export {
  SimpleChart,
  ChartWithEventComponent,
  ChartShowLoadingComponent,
  ChartAPIComponent,
  ThemeChartComponent,
  MapChartComponent,
  GraphComponent,
  LunarCalendarComponent,
  LiquidfillComponent,
  CalendarComponent,
};
