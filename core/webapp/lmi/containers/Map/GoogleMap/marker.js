 const  MarkerInfoWindow = (props) => {
  return (`<div class="isoInfoWindowWrapper">
      <div class="isoInfoWindow">
      <div class="isoInfoWindowImage">
        <img alt="#" src="${props.img}" />
      </div>
      <div class="isoInfoWindowDetails">
        <h3 class="isoHeading">${props.title}</h3>
        <p class="isoLocation">${props.location}</p>
      </div>
    </div>
  </div>`);
}


const Marker = (props) => {
  return (`<div class="marker-icon map-marker">
      <div class="marker-icon-wrapper">
        <i class="${props.iconClass}"></i>
      </div>
    </div>`)
} 

export {
  Marker,
  MarkerInfoWindow
}