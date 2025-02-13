import React, { Component } from 'react';
import 'leaflet';
import 'leaflet-routing-machine';
import leafletRoutingMachineCss from 'leaflet-routing-machine/dist/leaflet-routing-machine.css';
import leafletRoutingIcons from 'leaflet-routing-machine/dist/leaflet.routing.icons.png';
import { mapboxConfig } from '../../../../config';
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
    try {
      L.Routing
        .control({
          waypoints: [
            L.latLng(40.72143, -74.05729),
            L.latLng(40.6943, -74.074201)
          ],
          routeWhileDragging: true
        })
        .addTo(map);
    } catch (e) {}
  }
  render() {
    return (
      <div>
        <style>{leafletRoutingMachineCss}</style>
        <style>{leafletRoutingIcons}</style>
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
