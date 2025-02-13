const width = '100%';
const height = '400px';

const BarChart = {
  title: 'BarChart',
  key: 'BarChart',
  chartType: 'BarChart',
  width,
  height,
  data: [
    [
      'Year',
      'Trafic',
      {
        role: 'style',
      },
    ],
    ['2010', 10000, 'fill-color: #48A6F2; fill-opacity: 0.4'],
    ['2012', 21500, 'fill-color: #f64744; fill-opacity: 0.4'],
    ['2014', 56598, 'fill-color: #ffbf00; fill-opacity: 0.4'],
    ['2016', 85256, 'fill-color: #511E78; fill-opacity: 0.4'],
  ],
  options: {
    title: 'Visitor statistics from 2010 to 2016',
    titleTextStyle: {
      color: '#788195',
    },
    bar: {
      groupWidth: '95%',
    },
    legend: {
      position: 'none',
    },
    animation: {
      duration: 1000,
      easing: 'in',
      startup: true,
    },
    hAxis: {
      textStyle: {
        color: '#788195',
      },
    },
    vAxis: {
      textStyle: {
        color: '#788195',
      },
    },
    tooltip: {
      textStyle: {
        color: '#788195',
      },
    },
  },
  chartEvents: [
    {
      eventName: 'onmouseover',
    },
  ],
};

/* * * * * * * * * * * * * * * * * * * *
              Line Charts
* * * * * * * * * * * * * * * * * * * */
const lineChart = {
  title: 'Line Chart',
  chartType: 'LineChart',
  key: 'LineChart',
  width,
  height,
  columns: [
    {
      label: 'time',
      type: 'number',
    },
    {
      label: 'Air Passengers',
      type: 'number',
    },
  ],
  rows: [
    [1949, 11],
    [1949.08333333333, 11],
    [1949.16666666667, 13],
    [1949.25, 12],
    [1949.33333333333, 12],
    [1949.41666666667, 13],
    [1949.5, 14],
    [1949.58333333333, 14],
    [1949.66666666667, 136],
    [1949.75, 119],
    [1949.83333333333, 104],
    [1949.91666666667, 118],
    [1950, 115],
    [1950.08333333333, 126],
    [1950.16666666667, 141],
    [1950.25, 135],
    [1950.33333333333, 125],
    [1950.41666666667, 149],
    [1950.5, 170],
    [1950.58333333333, 170],
    [1950.66666666667, 158],
    [1950.75, 133],
    [1950.83333333333, 114],
    [1950.91666666667, 140],
    [1951, 145],
    [1951.08333333333, 150],
    [1951.16666666667, 178],
    [1951.25, 163],
    [1951.33333333333, 172],
    [1951.41666666667, 178],
    [1951.5, 199],
    [1951.58333333333, 199],
    [1951.66666666667, 184],
    [1951.75, 162],
    [1951.83333333333, 146],
    [1951.91666666667, 166],
    [1952, 171],
    [1952.08333333333, 180],
    [1952.16666666667, 193],
    [1952.25, 181],
    [1952.33333333333, 183],
    [1952.41666666667, 218],
    [1952.5, 230],
    [1952.58333333333, 242],
    [1952.66666666667, 209],
    [1952.75, 191],
    [1952.83333333333, 172],
    [1952.91666666667, 194],
    [1953, 196],
    [1953.08333333333, 196],
    [1953.16666666667, 236],
    [1953.25, 235],
    [1953.33333333333, 229],
    [1953.41666666667, 243],
    [1953.5, 264],
    [1953.58333333333, 272],
    [1953.66666666667, 237],
    [1953.75, 211],
    [1953.83333333333, 180],
    [1953.91666666667, 201],
    [1954, 204],
    [1954.08333333333, 188],
    [1954.16666666667, 235],
    [1954.25, 227],
    [1954.33333333333, 234],
    [1954.41666666667, 264],
    [1954.5, 302],
    [1954.58333333333, 293],
    [1954.66666666667, 259],
    [1954.75, 229],
    [1954.83333333333, 203],
    [1954.91666666667, 229],
    [1955, 242],
    [1955.08333333334, 233],
    [1955.16666666667, 267],
    [1955.25, 269],
    [1955.33333333334, 270],
    [1955.41666666667, 315],
    [1955.5, 364],
    [1955.58333333334, 347],
    [1955.66666666667, 312],
    [1955.75, 274],
    [1955.83333333334, 237],
    [1955.91666666667, 278],
    [1956, 284],
    [1956.08333333334, 277],
    [1956.16666666667, 317],
    [1956.25, 313],
    [1956.33333333334, 318],
    [1956.41666666667, 374],
    [1956.5, 413],
    [1956.58333333334, 405],
    [1956.66666666667, 355],
    [1956.75, 306],
    [1956.83333333334, 271],
    [1956.91666666667, 306],
    [1957, 315],
    [1957.08333333334, 301],
    [1957.16666666667, 356],
    [1957.25, 348],
    [1957.33333333334, 355],
    [1957.41666666667, 422],
    [1957.5, 465],
    [1957.58333333334, 467],
    [1957.66666666667, 404],
    [1957.75, 347],
    [1957.83333333334, 305],
    [1957.91666666667, 336],
    [1958, 340],
    [1958.08333333334, 318],
    [1958.16666666667, 362],
    [1958.25, 348],
    [1958.33333333334, 363],
    [1958.41666666667, 435],
    [1958.5, 491],
    [1958.58333333334, 505],
    [1958.66666666667, 404],
    [1958.75, 359],
    [1958.83333333334, 310],
    [1958.91666666667, 337],
    [1959, 360],
    [1959.08333333334, 342],
    [1959.16666666667, 406],
    [1959.25, 396],
    [1959.33333333334, 420],
    [1959.41666666667, 472],
    [1959.5, 548],
    [1959.58333333334, 559],
    [1959.66666666667, 463],
    [1959.75, 407],
    [1959.83333333334, 362],
    [1959.91666666667, 405],
    [1960, 417],
    [1960.08333333334, 391],
    [1960.16666666667, 419],
    [1960.25, 461],
    [1960.33333333334, 472],
    [1960.41666666667, 535],
    [1960.5, 622],
    [1960.58333333334, 606],
    [1960.66666666667, 508],
    [1960.75, 461],
    [1960.83333333334, 390],
    [1960.91666666667, 432],
  ],
  options: {
    legend: {
      textStyle: {
        color: '#788195',
      },
    },
    hAxis: {
      textStyle: {
        color: '#788195',
      },
      title: 'Time',
      titleTextStyle: {
        color: '#788195',
      },
    },
    vAxis: {
      textStyle: {
        color: '#788195',
      },
      title: 'Air Passengers',
      titleTextStyle: {
        color: '#788195',
      },
    },
    colors: ['#48A6F2'],
    dataOpacity: 1.0,
    animation: {
      duration: 1000,
      easing: 'in',
      startup: true,
    },
    tooltip: {
      textStyle: {
        color: '#788195',
      },
    },
  },
};

/* * * * * * * * * * * * * * * * * * * *
              Bubble Charts
* * * * * * * * * * * * * * * * * * * */
const BubbleChart = {
  title: 'Bubble Chart',
  key: 'BubbleChart',
  chartType: 'BubbleChart',
  width,
  height,
  data: [
    ['ID', 'Life Expectancy', 'Fertility Rate', 'Region', 'Population'],
    ['CAN', 80.66, 1.67, 'North America', 33739900],
    ['DEU', 79.84, 1.36, 'Europe', 81902307],
    ['DNK', 78.6, 1.84, 'Europe', 5523095],
    ['EGY', 72.73, 2.78, 'Middle East', 79716203],
    ['GBR', 80.05, 2, 'Europe', 61801570],
    ['IRN', 72.49, 1.7, 'Middle East', 73137148],
    ['IRQ', 68.09, 4.77, 'Middle East', 31090763],
    ['ISR', 81.55, 2.96, 'Middle East', 7485600],
    ['RUS', 68.6, 1.54, 'Europe', 141850000],
    ['USA', 78.09, 2.05, 'North America', 307007000],
  ],
  options: {
    title: 'Correlation between life expectancy, fertility rate and population of some world countries (2010)',
    titleTextStyle: {
      color: '#788195',
    },
    legend: {
      textStyle: {
        color: '#788195',
      },
    },
    hAxis: {
      textStyle: {
        color: '#788195',
      },
      title: 'Life Expectancy',
      titleTextStyle: {
        color: '#788195',
      },
    },
    vAxis: {
      textStyle: {
        color: '#788195',
      },
      title: 'Fertility Rate',
      titleTextStyle: {
        color: '#788195',
      },
    },
    bubble: {
      opacity: 0.6,
      stroke: '#ffffff',
      textStyle: {
        fontSize: 11,
        color: '#788195',
      },
    },
    tooltip: {
      textStyle: {
        color: '#788195',
      },
    },
    colors: ['#48A6F2', '#F55F82', '#ffbf00'],
    animation: {
      duration: 1000,
      easing: 'in',
      startup: true,
    },
  },
};

/* * * * * * * * * * * * * * * * * * * *
          Histogram Charts
* * * * * * * * * * * * * * * * * * * */
const Histogram = {
  title: 'Histogram',
  key: 'Histogram',
  chartType: 'Histogram',
  width,
  height,
  data: [
    ['Dinosaur', 'Length'],
    ['Acrocanthosaurus (top-spined lizard)', 12.2],
    ['Albertosaurus (Alberta lizard)', 9.1],
    ['Allosaurus (other lizard)', 12.2],
    ['Apatosaurus (deceptive lizard)', 22.9],
    ['Archaeopteryx (ancient wing)', 0.9],
    ['Argentinosaurus (Argentina lizard)', 36.6],
    ['Baryonyx (heavy claws)', 9.1],
    ['Brachiosaurus (arm lizard)', 30.5],
    ['Ceratosaurus (horned lizard)', 6.1],
    ['Coelophysis (hollow form)', 2.7],
    ['Compsognathus (elegant jaw)', 0.9],
    ['Deinonychus (terrible claw)', 2.7],
    ['Diplodocus (double beam)', 27.1],
    ['Dromicelomimus (emu mimic)', 3.4],
    ['Gallimimus (fowl mimic)', 5.5],
    ['Mamenchisaurus (Mamenchi lizard)', 21],
    ['Megalosaurus (big lizard)', 7.9],
    ['Microvenator (small hunter)', 1.2],
    ['Ornithomimus (bird mimic)', 4.6],
    ['Oviraptor (egg robber)', 1.5],
    ['Plateosaurus (flat lizard)', 7.9],
    ['Sauronithoides (narrow-clawed lizard)', 2],
    ['Seismosaurus (tremor lizard)', 45.7],
    ['Spinosaurus (spiny lizard)', 12.2],
    ['Supersaurus (super lizard)', 30.5],
    ['Tyrannosaurus (tyrant lizard)', 15.2],
    ['Ultrasaurus (ultra lizard)', 30.5],
    ['Velociraptor (swift robber)', 1.8],
  ],
  options: {
    title: 'Lengths of dinosaurs, in meters',
    titleTextStyle: {
      color: '#788195',
    },
    legend: {
      textStyle: {
        color: '#788195',
      },
    },
    colors: ['#511E78'],
    dataOpacity: 0.6,
    animation: {
      duration: 1000,
      easing: 'in',
      startup: true,
    },
    hAxis: {
      textStyle: {
        color: '#788195',
      },
    },
    vAxis: {
      textStyle: {
        color: '#788195',
      },
    },
    tooltip: {
      textStyle: {
        color: '#788195',
      },
    },
  },
};

/* * * * * * * * * * * * * * * * * * * *
              Scatter Charts
* * * * * * * * * * * * * * * * * * * */
const ScatterChart = {
  title: 'Scatter Chart',
  key: 'ScatterChart',
  chartType: 'ScatterChart',
  width,
  height,
  data: [
    ['Age', 'Weight'],
    [8, 12],
    [4, 10.5],
    [11, 14],
    [4, 5],
    [3, 3.5],
    [6.5, 7],
    [8, 11],
    [12, 8],
    [9.5, 14],
    [6.5, 12],
  ],
  options: {
    title: 'Age vs. Weight Comparison',
    titleTextStyle: {
      color: '#788195',
    },
    hAxis: {
      title: 'Age',
      titleTextStyle: {
        color: '#788195',
      },
      minValue: 0,
      maxValue: 15,
      textStyle: {
        color: '#788195',
      },
    },
    vAxis: {
      title: 'Weight',
      titleTextStyle: {
        color: '#788195',
      },
      minValue: 0,
      maxValue: 15,
      textStyle: {
        color: '#788195',
      },
    },
    legend: 'none',
    colors: ['#42A5F5'],
    dataOpacity: 0.8,
    tooltip: {
      textStyle: {
        color: '#788195',
      },
    },
  },
};

/* * * * * * * * * * * * * * * * * * * *
              Area Charts
* * * * * * * * * * * * * * * * * * * */
const AreaChart = {
  title: 'Area Chart',
  key: 'AreaChart',
  chartType: 'AreaChart',
  width,
  height,
  data: [
    ['Year', 'Sales', 'Expenses'],
    ['2013', 1000, 400],
    ['2014', 1170, 460],
    ['2015', 660, 1120],
    ['2016', 1030, 540],
  ],
  options: {
    legend: {
      textStyle: {
        color: '#788195',
      },
    },
    animation: {
      duration: 1000,
      easing: 'in',
      startup: true,
    },
    hAxis: {
      textStyle: {
        color: '#788195',
      },
    },
    vAxis: {
      textStyle: {
        color: '#788195',
      },
    },
    colors: ['#48A6F2', '#511E78'],
    dataOpacity: 0.6,
    tooltip: {
      textStyle: {
        color: '#788195',
      },
    },
  },
};

/* * * * * * * * * * * * * * * * * * * *
              Candle Stick Charts
* * * * * * * * * * * * * * * * * * * */
const CandlestickChart = {
  title: 'Candlestick Chart',
  key: 'CandlestickChart',
  chartType: 'CandlestickChart',
  width,
  height,
  data: [
    ['DAY', 'val1', 'val2', 'val3', 'val4'],
    ['Mon', 20, 28, 38, 45],
    ['Tue', 31, 38, 55, 66],
    ['Wed', 50, 55, 77, 80],
    ['Thu', 77, 77, 66, 50],
    ['Fri', 68, 66, 22, 15],
  ],
  options: {
    title: 'Visitors Per Day',
    titleTextStyle: {
      color: '#788195',
    },
    legend: 'none',
    hAxis: {
      textStyle: {
        color: '#788195',
      },
    },
    vAxis: {
      textStyle: {
        color: '#788195',
      },
    },
    animation: {
      duration: 1000,
      easing: 'in',
      startup: true,
    },
    colors: ['#48A6F2'],
    tooltip: {
      textStyle: {
        color: '#788195',
      },
    },
  },
};

/* * * * * * * * * * * * * * * * * * * *
              Combo Charts
* * * * * * * * * * * * * * * * * * * */
const ComboChart = {
  title: 'Combo Chart',
  key: 'ComboChart',
  chartType: 'ComboChart',
  width,
  height,
  data: [
    [
      'Month',
      'Bolivia',
      'Ecuador',
      'Madagascar',
      'Papua New Guinea',
      'Rwanda',
      'Average',
    ],
    ['2004/05', 165, 938, 522, 998, 450, 614.6],
    ['2005/06', 135, 1120, 599, 1268, 288, 682],
    ['2006/07', 157, 1167, 587, 807, 397, 623],
    ['2007/08', 139, 1110, 615, 968, 215, 609.4],
    ['2008/09', 136, 691, 629, 1026, 366, 569.6],
  ],
  options: {
    title: 'Monthly Coffee Production by Country',
    titleTextStyle: {
      color: '#788195',
    },
    legend: {
      textStyle: {
        color: '#788195',
      },
    },
    hAxis: {
      textStyle: {
        color: '#788195',
      },
      title: 'Cups',
      titleTextStyle: {
        color: '#788195',
      },
    },
    vAxis: {
      textStyle: {
        color: '#788195',
      },
      title: 'Month',
      titleTextStyle: {
        color: '#788195',
      },
    },
    seriesType: 'bars',
    series: {
      5: {
        type: 'line',
      },
    },
    animation: {
      duration: 1000,
      easing: 'in',
      startup: true,
    },
    colors: ['#00b16a', '#ff6384', '#511E78', '#01C0C8', '#ffbf00', '#48A6F2'],
    dataOpacity: 0.6,
    tooltip: {
      textStyle: {
        color: '#788195',
      },
    },
  },
};

/* * * * * * * * * * * * * * * * * * * *
              Donut Charts
* * * * * * * * * * * * * * * * * * * */
const DonutChart = {
  title: 'Donut Chart',
  key: 'DonutChart',
  chartType: 'PieChart',
  width,
  height,
  data: [
    ['Task', 'Hours per Day'],
    ['Work', 11],
    ['Eat', 2],
    ['Commute', 2],
    ['Watch TV', 2],
    ['Sleep', 7],
  ],
  options: {
    title: 'My Daily Activities',
    titleTextStyle: {
      color: '#788195',
    },
    legend: {
      textStyle: {
        color: '#788195',
      },
    },
    pieHole: 0.4,
    pieSliceTextStyle: {
      color: '#ffffff',
    },
    is3D: true,
    colors: ['#9678AE', '#F99FB4', '#C8E4FB', '#01C0C8', '#ffbf00'],
    tooltip: {
      textStyle: {
        color: '#788195',
      },
    },
  },
};

/* * * * * * * * * * * * * * * * * * * *
          Stepped Area Charts
* * * * * * * * * * * * * * * * * * * */
const SteppedAreaChart = {
  title: 'Stepped Area Chart',
  key: 'SteppedAreaChart',
  chartType: 'SteppedAreaChart',
  width,
  height,
  data: [
    ['Director (Year)', 'Rotten Tomatoes', 'IMDB'],
    ['Alfred Hitchcock (1935)', 8.4, 7.9],
    ['Ralph Thomas (1959)', 6.9, 6.5],
    ['Don Sharp (1978)', 6.5, 6.4],
    ['James Hawes (2008)', 4.4, 6.2],
  ],
  options: {
    title: 'The decline of The 39 Steps',
    titleTextStyle: {
      color: '#788195',
    },
    legend: {
      textStyle: {
        color: '#788195',
      },
    },
    animation: {
      duration: 1000,
      easing: 'in',
      startup: true,
    },
    colors: ['#511E78', '#F55F82'],
    hAxis: {
      textStyle: {
        color: '#788195',
      },
    },
    vAxis: {
      textStyle: {
        color: '#788195',
      },
      title: 'Accumulated Rating',
      titleTextStyle: {
        color: '#788195',
      },
    },
    isStacked: true,
    tooltip: {
      textStyle: {
        color: '#788195',
      },
    },
  },
};

/* * * * * * * * * * * * * * * * * * * *
              Table
* * * * * * * * * * * * * * * * * * * */
const Table = {
  title: 'Table',
  key: 'Table',
  chartType: 'Table',
  chartPackages: ['table'],
  width,
  height,
  columns: [
    {
      type: 'string',
      label: 'Name',
    },
    {
      type: 'number',
      label: 'Salary',
    },
    {
      type: 'boolean',
      label: 'Full Time Employee',
    },
  ],
  rows: [
    [
      'Mike',
      {
        v: 10000,
        f: '$10,000',
      },
      true,
    ],
    [
      'Jim',
      {
        v: 8000,
        f: '$8,000',
      },
      false,
    ],
    [
      'Alice',
      {
        v: 12500,
        f: '$12,500',
      },
      true,
    ],
    [
      'Bob',
      {
        v: 7000,
        f: '$7,000',
      },
      true,
    ],
  ],
};

/* * * * * * * * * * * * * * * * * * * *
            Timeline Charts
* * * * * * * * * * * * * * * * * * * */
const Timeline = {
  title: 'Timeline',
  key: 'Timeline',
  chartType: 'Timeline',
  chartPackage: 'timeline',
  width,
  height,
  columns: [
    {
      id: 'Term',
      type: 'string',
    },
    {
      id: 'President',
      type: 'string',
    },
    {
      id: 'Start',
      type: 'date',
    },
    {
      id: 'End',
      type: 'date',
    },
  ],
  rows: [
    [
      '1',
      'Washington',
      new Date('1789-04-29T18:00:00.000Z'),
      new Date('1797-03-03T18:00:00.000Z'),
    ],
    [
      '2',
      'Adams',
      new Date('1797-03-03T18:00:00.000Z'),
      new Date('1801-03-03T18:00:00.000Z'),
    ],
    [
      '3',
      'Jefferson',
      new Date('1801-03-03T18:00:00.000Z'),
      new Date('1809-03-03T18:00:00.000Z'),
    ],
  ],
  options: {
    colors: ['#ffbf00', '#F55F82', '#48A6F2'],
    tooltip: {
      textStyle: {
        color: '#788195',
      },
    },
  },
};

/* * * * * * * * * * * * * * * * * * * *
              Tree Map
* * * * * * * * * * * * * * * * * * * */
const TreeMap = {
  title: 'TreeMap',
  key: 'TreeMap',
  chartType: 'TreeMap',
  chartPackages: ['treemap'],
  width,
  height,
  data: [
    [
      'Location',
      'Parent',
      'Market trade volume (size)',
      'Market increase/decrease (color)',
    ],
    ['Global', null, 0, 0],
    ['America', 'Global', 0, 0],
    ['Europe', 'Global', 0, 0],
    ['Asia', 'Global', 0, 0],
    ['Australia', 'Global', 0, 0],
    ['Africa', 'Global', 0, 0],
    ['Brazil', 'America', 11, 10],
    ['USA', 'America', 52, 31],
    ['Mexico', 'America', 24, 12],
    ['Canada', 'America', 16, -23],
    ['France', 'Europe', 42, -11],
    ['Germany', 'Europe', 31, -2],
    ['Sweden', 'Europe', 22, -13],
    ['Italy', 'Europe', 17, 4],
    ['UK', 'Europe', 21, -5],
    ['China', 'Asia', 36, 4],
    ['Japan', 'Asia', 20, -12],
    ['India', 'Asia', 40, 63],
    ['Laos', 'Asia', 4, 34],
    ['Mongolia', 'Asia', 1, -5],
    ['Israel', 'Asia', 12, 24],
    ['Iran', 'Asia', 18, 13],
    ['Pakistan', 'Asia', 11, -52],
    ['Egypt', 'Africa', 21, 0],
    ['S. Africa', 'Africa', 30, 43],
    ['Sudan', 'Africa', 12, 2],
    ['Congo', 'Africa', 10, 12],
    ['Zaire', 'Africa', 8, 10],
  ],
  options: {
    minColor: '#511E78',
    midColor: '#C8E4FB',
    maxColor: '#48A6F2',
  },
};

/* * * * * * * * * * * * * * * * * * * *
          Trend Lines Charts
* * * * * * * * * * * * * * * * * * * */
const TrendLines = {
  title: 'TrendLines',
  key: 'TrendLines',
  chartType: 'ScatterChart',
  width,
  height,
  data: [
    ['Diameter', 'Age'],
    [8, 37],
    [4, 19.5],
    [11, 52],
    [4, 22],
    [3, 16.5],
    [6.5, 32.8],
    [14, 72],
  ],
  options: {
    title: 'Age of sugar maples vs. trunk diameter, in inches',
    titleTextStyle: {
      color: '#788195',
    },
    hAxis: {
      textStyle: {
        color: '#788195',
      },
      title: 'Diameter',
      titleTextStyle: {
        color: '#788195',
      },
    },
    vAxis: {
      textStyle: {
        color: '#788195',
      },
      title: 'Age',
      titleTextStyle: {
        color: '#788195',
      },
    },
    legend: 'none',
    trendlines: {
      0: {
        type: 'exponential',
        colors: '#48A6F2',
      },
    },
    tooltip: {
      textStyle: {
        color: '#788195',
      },
    },
  },
};

/* * * * * * * * * * * * * * * * * * * *
            Water Fall Charts
* * * * * * * * * * * * * * * * * * * */
const Waterfall = {
  title: 'Waterfall',
  key: 'Waterfall',
  chartType: 'CandlestickChart',
  width,
  height,
  data: [
    ['DAY', 'val1', 'val2', 'val3', 'val4'],
    ['Mon', 20, 28, 38, 45],
    ['Tue', 31, 38, 55, 66],
    ['Wed', 50, 55, 77, 80],
    ['Thu', 77, 77, 66, 50],
    ['Fri', 68, 66, 22, 15],
  ],
  options: {
    legend: 'none',
    bar: {
      groupWidth: '100%',
    },
    hAxis: {
      textStyle: {
        color: '#788195',
      },
    },
    vAxis: {
      textStyle: {
        color: '#788195',
      },
    },
    animation: {
      duration: 1000,
      easing: 'in',
      startup: true,
    },
    tooltip: {
      textStyle: {
        color: '#788195',
      },
    },
    candlestick: {
      fallingColor: {
        strokeWidth: 0,
        fill: '#F55F82',
      },
      risingColor: {
        strokeWidth: 0,
        fill: '#48A6F2',
      },
    },
  },
};

/* * * * * * * * * * * * * * * * * * * *
              Gantt Charts
* * * * * * * * * * * * * * * * * * * */
const Gantt = {
  title: 'Gantt',
  key: 'Gantt',
  chartType: 'Gantt',
  chartPackages: ['gantt'],
  width,
  height,
  columns: [
    {
      id: 'Task ID',
      type: 'string',
    },
    {
      id: 'Task Name',
      type: 'string',
    },
    {
      id: 'Start Date',
      type: 'date',
    },
    {
      id: 'End Date',
      type: 'date',
    },
    {
      id: 'Duration',
      type: 'number',
    },
    {
      id: 'Percent Complete',
      type: 'number',
    },
    {
      id: 'Dependencies',
      type: 'string',
    },
  ],
  rows: [
    [
      'Research',
      'Find sources',
      new Date('2014-12-31T18:00:00.000Z'),
      new Date('2015-01-04T18:00:00.000Z'),
      null,
      100,
      null,
    ],
    [
      'Write',
      'Write paper',
      null,
      new Date('2015-01-08T18:00:00.000Z'),
      259200000,
      25,
      'Research,Outline',
    ],
    [
      'Cite',
      'Create bibliography',
      null,
      new Date('2015-01-06T18:00:00.000Z'),
      86400000,
      20,
      'Research',
    ],
    [
      'Complete',
      'Hand in paper',
      null,
      new Date('2015-01-09T18:00:00.000Z'),
      86400000,
      0,
      'Cite,Write',
    ],
    [
      'Outline',
      'Outline paper',
      null,
      new Date('2015-01-05T18:00:00.000Z'),
      86400000,
      100,
      'Research',
    ],
  ],
  options: {
    tooltip: {
      textStyle: {
        color: '#788195',
      },
    },
    gantt: {
      criticalPathEnabled: false, // Critical path arrows will be the same as other arrows.
      arrow: {
        angle: 100,
        width: 2,
        color: '#9678AE',
        radius: 0,
      },
    },
  },
};

/* * * * * * * * * * * * * * * * * * * *
              Word Tree Charts
* * * * * * * * * * * * * * * * * * * */
const WordTree = {
  title: 'WordTree',
  key: 'WordTree',
  chartType: 'WordTree',
  chartPackages: ['wordtree'],
  width,
  height,
  data: [
    ['Phrases'],
    ['cats are better than dogs'],
    ['cats eat kibble'],
    ['cats are better than hamsters'],
    ['cats are awesome'],
    ['cats are people too'],
    ['cats eat mice'],
    ['cats meowing'],
    ['cats in the cradle'],
    ['cats eat mice'],
    ['cats in the cradle lyrics'],
    ['cats eat kibble'],
    ['cats for adoption'],
    ['cats are family'],
    ['cats eat mice'],
    ['cats are better than kittens'],
    ['cats are evil'],
    ['cats are weird'],
    ['cats eat mice'],
  ],
  options: {
    tooltip: {
      textStyle: {
        color: '#788195',
      },
    },
    wordtree: {
      format: 'implicit',
      word: 'cats',
    },
  },
};

export {
  BarChart,
  lineChart,
  BubbleChart,
  Histogram,
  ScatterChart,
  AreaChart,
  CandlestickChart,
  ComboChart,
  DonutChart,
  SteppedAreaChart,
  Table,
  Timeline,
  TreeMap,
  TrendLines,
  Waterfall,
  Gantt,
  WordTree,
};
