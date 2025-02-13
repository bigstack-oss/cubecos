const customIcon = '/static/image/map-pin-2.svg';
const customIconShadow = '/static/image/marker-shadow.png';
const infoWindowImg1 = '/static/image/image1.jpg';
const infoWindowImg2 = '/static/image/image3.jpg';
const infoWindowImg3 = '/static/image/image4.jpg';
const infoWindowImg4 = '/static/image/image5.jpg';

const basicMarkers = [
  {
    position: [40.68792, -74.01626],
    popupText: `
      <div class="isoInfoWindowImage">
        <img src=${infoWindowImg1} alt="" />
      </div>
      <div class="isoInfoWindowDetails">
        <h3>Washington Square Park</h3>
      </div>`,
  },
  {
    position: [40.72143, -74.05729],
    popupText: `
      <div class="isoInfoWindowImage">
        <img src=${infoWindowImg2} alt="" />
      </div>
      <div class="isoInfoWindowDetails">
        <h3>Washington Square Village</h3>
      </div>`,
  },
  {
    position: [40.7215, -73.999],
    popupText: `
      <div class="isoInfoWindowImage">
        <img src=${infoWindowImg3} alt="" />
      </div>
      <div class="isoInfoWindowDetails">
        <h3>Washington Square</h3>
      </div>`,
  },
  {
    position: [40.696518, -73.95352],
    popupText: `
      <div class="isoInfoWindowImage">
        <img src=${infoWindowImg4} alt="" />
      </div>
      <div class="isoInfoWindowDetails">
        <h3>New York University</h3>
      </div>`,
  },
  {
    position: [40.6943, -74.074201],
    popupText: `
      <div class="isoInfoWindowImage">
        <img src=${infoWindowImg2} alt="" />
      </div>
      <div class="isoInfoWindowDetails">
        <h3>Library Golf Club</h3>
      </div>`,
  },
];

const customIconMarkers = [
  {
    position: [40.68792, -74.01626],
    iconUrl: customIcon,
    shadowUrl: customIconShadow,
    popupText: `
      <div class="isoInfoWindowImage">
        <img src=${infoWindowImg2} alt="" />
      </div>
      <div class="isoInfoWindowDetails">
        <h3>Washington Square Village</h3>
      </div>`,
  },
];

const customHtmlMarker = [
  {
    position: [40.68792, -74.01626],
    html: `
      <MarkerWrapper class="marker-icon-wrapper">
        <i class="ion-flame" />
      </MarkerWrapper>`,
    className: 'marker-icon',
    popupText: `
      <div class="isoInfoWindowImage">
        <img src=${infoWindowImg2} alt="" />
      </div>
      <div class="isoInfoWindowDetails">
        <h3>Washington Square Village</h3>
      </div>`,
  },
];

const markerCluster = [
  {
    position: [40.68792, -74.01626],
    iconUrl: customIcon,
    iconSize: [40, 40],
    popupText: `
      <div class="isoInfoWindowImage">
        <img src=${infoWindowImg2} alt="" />
      </div>
      <div class="isoInfoWindowDetails">
        <h3>Washington Square Village</h3>
      </div>`,
  },
  {
    position: [40.72143, -74.05729],
    iconUrl: customIcon,
    popupText: `
      <div class="isoInfoWindowImage">
        <img src=${infoWindowImg2} alt="" />
      </div>
      <div class="isoInfoWindowDetails">
        <h3>Washington Square Village</h3>
      </div>`,
  },
  {
    position: [40.7215, -73.999],
    iconUrl: customIcon,
    popupText: `
      <div class="isoInfoWindowImage">
        <img src=${infoWindowImg1} alt="" />
      </div>
      <div class="isoInfoWindowDetails">
        <h3>Washington Square</h3>
      </div>`,
  },
  {
    position: [40.696518, -73.95352],
    iconUrl: customIcon,
    popupText: `
      <div class="isoInfoWindowImage">
        <img src=${infoWindowImg3} alt="" />
      </div>
      <div class="isoInfoWindowDetails">
        <h3>New York University</h3>
      </div>`,
  },
  {
    position: [40.6943, -74.074201],
    iconUrl: customIcon,
    popupText: `
      <div class="isoInfoWindowImage">
        <img src=${infoWindowImg4} alt="" />
      </div>
      <div class="isoInfoWindowDetails">
        <h3>Library Golf Club</h3>
      </div>`,
  },
  {
    position: [40.6943, -74.074201],
    iconUrl: customIcon,
    popupText: `
      <div class="isoInfoWindowImage">
        <img src=${infoWindowImg1} alt="" />
      </div>
      <div class="isoInfoWindowDetails">
        <h3>Library Golf Club Old Portion</h3>
      </div>`,
  },
];

const markerRouting = {
  postion_start: [40.72143, -74.05729],
  iconUrl: customIcon,
  postion_end: [40.6943, -74.074201],
};

export {
  basicMarkers,
  customIconMarkers,
  customHtmlMarker,
  markerCluster,
  markerRouting,
};
