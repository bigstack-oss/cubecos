import React, { Component } from 'react';
import { posts } from '../config.js';
import { googleConfig } from '../../../../config';
import { GoogleApiWrapper } from 'google-maps-react';
import { Marker, MarkerInfoWindow } from '../marker';
import BasicMapWrapper from './map.style';

class BasicMarkerMap extends Component {
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
    const self = this;
    const Map = new google.maps.Map(element, {
      zoom: this.state.zoom,
      center: this.state.center,
      scrollwheel: false,
      mapTypeControlOptions: {
        style: google.maps.MapTypeControlStyle.HORIZONTAL_BAR,
        position: google.maps.ControlPosition.TOP_RIGHT,
      },
    });
    const RichMarker = require('js-rich-marker');
    const InfoBubble = require('js-info-bubble');
    posts.map(post => {
      const marker = RichMarker
        ? new RichMarker.RichMarker({
            map: Map,
            animation: google.maps.Animation.DROP,
            flat: true,
            content: Marker(post.marker),
            position: new google.maps.LatLng(post.lat, post.lng),
          })
        : new google.maps.Marker({
            position: new google.maps.LatLng(post.lat, post.lng),
            map: Map,
            flat: true,
            animation: google.maps.Animation.DROP,
            content: Marker(post.marker),
          });
      const infoBubble = new InfoBubble({
        maxWidth: 280,
        minWidth: 280,
        maxHeight: 255,
        minHeight: 255,
        shadowStyle: 0,
        padding: 0,
        backgroundColor: '#ffffff',
        position: new google.maps.LatLng(post.lat, post.lng),
        borderRadius: 0,
        arrowSize: 10,
        borderWidth: 0,
        disableAnimation: true,
        autopanMargin: 0,
        hideCloseButton: false,
        arrowStyle: 0,
        content: MarkerInfoWindow(post),
      });
      marker.addListener('click', function() {
        if (self.infowindow) {
          self.infowindow.close();
        }
        infoBubble.open(Map, marker);
        self.infowindow = infoBubble;
      });
      return true;
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
})(BasicMarkerMap);
