const infoWindowImg1 = '/static/image/image1.jpg';
const infoWindowImg2 = '/static/image/image3.jpg';
const infoWindowImg3 = '/static/image/image4.jpg';
const infoWindowImg4 = '/static/image/image5.jpg';

const SnazyMapStyle = JSON.stringify([
  {
    featureType: 'all',
    elementType: 'labels.text.fill',
    stylers: [{ saturation: 36 }, { color: '#000000' }, { lightness: 40 }]
  },
  {
    featureType: 'all',
    elementType: 'labels.text.stroke',
    stylers: [{ visibility: 'on' }, { color: '#000000' }, { lightness: 16 }]
  },
  {
    featureType: 'all',
    elementType: 'labels.icon',
    stylers: [{ visibility: 'off' }]
  },
  {
    featureType: 'administrative',
    elementType: 'geometry.fill',
    stylers: [{ color: '#000000' }, { lightness: 20 }]
  },
  {
    featureType: 'administrative',
    elementType: 'geometry.stroke',
    stylers: [{ color: '#000000' }, { lightness: 17 }, { weight: 1.2 }]
  },
  {
    featureType: 'administrative',
    elementType: 'labels',
    stylers: [{ visibility: 'off' }]
  },
  {
    featureType: 'administrative.country',
    elementType: 'all',
    stylers: [{ visibility: 'simplified' }]
  },
  {
    featureType: 'administrative.country',
    elementType: 'geometry',
    stylers: [{ visibility: 'simplified' }]
  },
  {
    featureType: 'administrative.country',
    elementType: 'labels.text',
    stylers: [{ visibility: 'simplified' }]
  },
  {
    featureType: 'administrative.province',
    elementType: 'all',
    stylers: [{ visibility: 'off' }]
  },
  {
    featureType: 'administrative.locality',
    elementType: 'all',
    stylers: [
      { visibility: 'simplified' },
      { saturation: '-100' },
      { lightness: '30' }
    ]
  },
  {
    featureType: 'administrative.neighborhood',
    elementType: 'all',
    stylers: [{ visibility: 'off' }]
  },
  {
    featureType: 'administrative.land_parcel',
    elementType: 'all',
    stylers: [{ visibility: 'off' }]
  },
  {
    featureType: 'landscape',
    elementType: 'all',
    stylers: [
      { visibility: 'simplified' },
      { gamma: '0.00' },
      { lightness: '74' }
    ]
  },
  {
    featureType: 'landscape',
    elementType: 'geometry',
    stylers: [{ color: '#34334f' }, { lightness: '-37' }]
  },
  {
    featureType: 'landscape.man_made',
    elementType: 'all',
    stylers: [{ lightness: '3' }]
  },
  { featureType: 'poi', elementType: 'all', stylers: [{ visibility: 'off' }] },
  {
    featureType: 'poi',
    elementType: 'geometry',
    stylers: [{ color: '#000000' }, { lightness: 21 }]
  },
  {
    featureType: 'road',
    elementType: 'geometry',
    stylers: [{ visibility: 'simplified' }]
  },
  {
    featureType: 'road.highway',
    elementType: 'geometry.fill',
    stylers: [{ color: '#2d2c45' }, { lightness: '0' }]
  },
  {
    featureType: 'road.highway',
    elementType: 'geometry.stroke',
    stylers: [{ color: '#000000' }, { lightness: 29 }, { weight: 0.2 }]
  },
  {
    featureType: 'road.highway',
    elementType: 'labels.text.fill',
    stylers: [{ color: '#7d7c9b' }, { lightness: '43' }]
  },
  {
    featureType: 'road.highway',
    elementType: 'labels.text.stroke',
    stylers: [{ visibility: 'off' }]
  },
  {
    featureType: 'road.arterial',
    elementType: 'geometry',
    stylers: [{ color: '#2d2c45' }, { lightness: '1' }]
  },
  {
    featureType: 'road.arterial',
    elementType: 'labels.text',
    stylers: [{ visibility: 'on' }]
  },
  {
    featureType: 'road.arterial',
    elementType: 'labels.text.fill',
    stylers: [{ color: '#7d7c9b' }]
  },
  {
    featureType: 'road.arterial',
    elementType: 'labels.text.stroke',
    stylers: [{ visibility: 'off' }]
  },
  {
    featureType: 'road.local',
    elementType: 'geometry',
    stylers: [{ color: '#2d2c45' }, { lightness: '-1' }, { gamma: '1' }]
  },
  {
    featureType: 'road.local',
    elementType: 'labels.text',
    stylers: [{ visibility: 'on' }, { hue: '#ff0000' }]
  },
  {
    featureType: 'road.local',
    elementType: 'labels.text.fill',
    stylers: [{ color: '#7d7c9b' }, { lightness: '-31' }]
  },
  {
    featureType: 'road.local',
    elementType: 'labels.text.stroke',
    stylers: [{ visibility: 'off' }]
  },
  {
    featureType: 'transit',
    elementType: 'geometry',
    stylers: [{ color: '#2d2c45' }, { lightness: '-36' }]
  },
  {
    featureType: 'water',
    elementType: 'geometry',
    stylers: [{ color: '#2d2c45' }, { lightness: '0' }, { gamma: '1' }]
  },
  {
    featureType: 'water',
    elementType: 'labels.text.stroke',
    stylers: [{ visibility: 'off' }]
  }
]);
// import infoWindowLoc from '../../../image/work.jpg';
// import infoWindowLoc from '../../../image/work.jpg';
// import infoWindowLoc from '../../../image/work.jpg';
const posts = [
  {
    ID: 1,
    title: 'Manhatan Lake Cafe',
    location: 'Manhatan, NY',
    img: infoWindowImg1,
    lat: 40.78306,
    lng: -73.971249,
    marker: {
      borderStyle: 'double',
      borderColor: 'grey',
      fontFamily: 'ionicons',
      iconClass: 'ion-android-pin'
    }
  },
  {
    ID: 2,
    title: 'Ridgewood Moon Castle',
    location: 'Ridgewood, NY',
    img: infoWindowImg2,
    lat: 40.779545,
    lng: -74.023751,
    marker: {
      borderStyle: 'double',
      borderColor: 'red',
      fontFamily: 'ionicons',
      iconClass: 'ion-paper-airplane'
    }
  },
  {
    ID: 3,
    title: 'Astoria Cafe',
    location: 'Astoria Park, NY',
    img: infoWindowImg3,
    lat: 40.779668,
    lng: -73.921589,
    marker: {
      borderStyle: 'double',
      borderColor: 'green',
      fontFamily: 'ionicons',
      iconClass: 'ion-chatbubbles'
    }
  },
  {
    ID: 4,
    title: 'Malcom hill',
    location: 'Malcom X, NY',
    img: infoWindowImg4,
    lat: 40.809657,
    lng: -73.944201,
    marker: {
      borderStyle: 'double',
      borderColor: 'yellow',
      fontFamily: 'ionicons',
      iconClass: 'ion-coffee'
    }
  }
];

export { SnazyMapStyle, posts };
