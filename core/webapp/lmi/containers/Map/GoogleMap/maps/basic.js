import React, { Component } from 'react';
import { posts } from '../config.js';
import { googleConfig } from '../../../../config';
import { GoogleApiWrapper } from 'google-maps-react';
import BasicMapWrapper from './map.style';

class BasicMap extends Component {
  constructor(props) {
    super(props);
    this.loadMap = this.loadMap.bind(this);
    this.state = {
      center: { lat: 40.78306, lng: -73.971249 }, // 40.783060, -73.971249
      zoom: 13,
      posts,
      infoWindow: null,
    };
  }
  loadMap(element) {
    const { google } = this.props;
    if (!element || !google) return;
    new google.maps.Map(element, {
      zoom: this.state.zoom,
      center: this.state.center,
      scrollwheel: false,
      mapTypeControlOptions: {
        style: google.maps.MapTypeControlStyle.HORIZONTAL_BAR,
        position: google.maps.ControlPosition.TOP_RIGHT,
      },
    });
  }
  render() {
    const { loaded } = this.props;
    return (
      <div>
        {loaded ? (
          <BasicMapWrapper>
            <div
              className="isoGoogleMap"
              style={{ height: '650px', width: '100%' }}
              ref={this.loadMap}
            />
          </BasicMapWrapper>
        ) : (
          <span>API is Loading</span>
        )}
      </div>
    );
  }
}

export default GoogleApiWrapper({
  apiKey: googleConfig.apiKey,
})(BasicMap);
