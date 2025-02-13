import React, { Component } from 'react';
import { mapboxConfig } from '../../../../config';
import 'leaflet';
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
  }
  render() {
    return (
      <LeafletMapWrapper className="isoLeafletMap">
        <div
          id="basic-map"
          style={{ height: '400px', width: '100%' }}
          ref={this.mountMap}
        />
      </LeafletMapWrapper>
    );
  }
}
