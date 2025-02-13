import React from 'react';
import Link from 'next/link';
import IntlMessages from '../../components/utility/intlMessages';
import FiveZeroZeroStyleWrapper from './500.style';
const Image = '/static/image/rob.png';

class FiveHundred extends React.Component {
  render() {
    return (
      <FiveZeroZeroStyleWrapper className="iso500Page">
        <div className="iso500Content">
          <h1>
            <IntlMessages id="page500.title" />
          </h1>
          <h3>
            <IntlMessages id="page500.subTitle" />
          </h3>
          <p>
            <IntlMessages id="page500.description" />
          </p>
          <button type="button">
            <Link href="/dashboard">
              <span className="isoMenuHolder">
                <span className="nav-text">             
                  <IntlMessages id="page500.backButton" />
                </span>
              </span>
            </Link>
          </button>
        </div>

        <div className="iso500Artwork">
          <img alt="#" src={Image} />
        </div>
      </FiveZeroZeroStyleWrapper>
    );
  }
}

export default FiveHundred;
