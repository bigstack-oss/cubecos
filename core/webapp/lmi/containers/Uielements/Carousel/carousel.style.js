import styled from 'styled-components';
import { palette } from 'styled-theme';
import WithDirection from '../../../config/withDirection';

const CarouselStyleWrapper = styled.div`
  .isoCarousalDemoContainer {
    width: 100%;
    display: flex;
    flex-flow: row wrap;
  }
  .ant-carousel {
    .slick-slider {
      direction: ${props => (props['data-rtl'] === 'rtl' ? 'ltr' : 'inherit')};
      .slick-track {
        left: auto;
        right: 0;

        .slick-slide {
          text-align: center;
          height: 160px;
          line-height: 160px;
          background: ${palette('secondary', 4)};
          color: #fff;
          overflow: hidden;
          float: left !important;
        }
      }
    }
  }
`;

export default WithDirection(CarouselStyleWrapper);
