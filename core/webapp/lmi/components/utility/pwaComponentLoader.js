import React from 'react';
import PwaLoader from './pwaloader.style';

export default PWAComponentLoader =>
  <PwaLoader>
    <div className="pwaComponentLoaderWrapper">
      <div className="pwaLoader">
        <div className="animated-background">
          <div className="background-masker header-top" />
          <div className="background-masker header-right" />
          <div className="background-masker header-bottom" />
          <div className="background-masker subheader-right" />
          <div className="background-masker content-top" />
          <div className="background-masker content-first-end" />
          <div className="background-masker content-second-line" />
          <div className="background-masker content-second-end" />
          <div className="background-masker content-third-line" />
          <div className="background-masker content-third-end" />
        </div>
      </div>
    </div>
  </PwaLoader>;
