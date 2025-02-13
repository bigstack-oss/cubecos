import React, { Component } from 'react';
import styled from 'styled-components';
import 'leaflet';
import 'leaflet.markercluster';
import MarkerClusterCss from 'leaflet.markercluster/dist/MarkerCluster.css';
import MarkerClusterCssDefault from 'leaflet.markercluster/dist/MarkerCluster.Default.css';

import { mapboxConfig } from '../../../../config';
import { markerCluster } from '../config';
import LeafletMapWrapper from './map.style';

export default class extends Component {
  constructor(props) {
    super(props);
    this.mountMap = this.mountMap.bind(this);
  }
  mountMap(element) {
    if (!element) return;
    const { L } = window;
    const map = L.map(element).setView(
      mapboxConfig.center,
      !isNaN(mapboxConfig.defaultZoom) ? mapboxConfig.defaultZoom : 13
    );
    const osmAttr =
      '&copy; <a href="http://openstreetmap.org">OpenStreetMap</a> contributors';
    L.tileLayer(mapboxConfig.tileLayer, {
      maxZoom: !isNaN(mapboxConfig.maxZoom) ? mapboxConfig.maxZoom : 18,
      attribution: osmAttr
    }).addTo(map);

    let markers = L.markerClusterGroup();

    markerCluster.map(singleMarker => {
      var customIcon = L.icon({
        iconUrl: singleMarker.iconUrl,
        iconSize: [40, 40], // size of the icon
        popupAnchor: [0, -20] // point from which the popup should open relative to the iconAnchor
      });
      return markers.addLayer(
        L.marker(singleMarker.position, { icon: customIcon })
          .bindPopup(singleMarker.popupText)
          .openPopup()
      );
    });
    map.addLayer(markers);
  }
  render() {
    return (
      <div>
        <style>{MarkerClusterCss}</style>
        <style>{MarkerClusterCssDefault}</style>
        <LeafletMapWrapper className="isoLeafletMap">
          <div
            id="basic-map-marker"
            style={{ height: '400px', width: '100%' }}
            ref={this.mountMap}
          />
        </LeafletMapWrapper>
      </div>
    );
  }
}
