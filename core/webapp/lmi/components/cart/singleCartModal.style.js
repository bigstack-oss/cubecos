import styled from 'styled-components';
import { palette } from 'styled-theme';
import { transition } from '../../config/style-util';
import WithDirection from '../../config/withDirection';

const TopbarCartWrapper = styled.div`
  width: 100%;
  display: flex;
  align-items: center;
  padding: 15px 30px;
  flex-shrink: 0;
  position: relative;
  border-bottom: 1px solid ${palette('border', 2)};
  ${transition()};

  .isoItemImage {
    width: 50px;
    height: 50px;
    flex-shrink: 0;
    display: flex;
    align-items: center;
    justify-content: center;

    img {
      width: 100%;
      height: 100%;
      object-fit: cover;
    }
  }

  .isoCartDetails {
    width: 100%;
    display: flex;
    padding: ${props =>
      props['data-rtl'] === 'rtl' ? '0 20px 0 0' : '0 0 0 20px'};
    flex-direction: column;
    text-align: ${props => (props['data-rtl'] === 'rtl' ? 'right' : 'left')};

    h3 {
      margin: 0 0 5px;
      line-height: 1;

      a {
        font-size: 13px;
        font-weight: 500;
        color: ${palette('text', 0)};
        line-height: 1.3;
        text-decoration: none;
      }
    }

    p {
      display: flex;
      margin: 0;

      span {
        font-size: 12px;
        font-weight: 400;
        color: ${palette('text', 2)};
        line-height: 1.2;

        &.itemMultiplier {
          padding: 0 3px;
        }
      }
    }
  }

  .isoItemRemove {
    position: absolute;
    right: ${props => (props['data-rtl'] === 'rtl' ? 'inherit' : '15px')};
    left: ${props => (props['data-rtl'] === 'rtl' ? '15px' : 'inherit')};
    font-size: 13px;
    font-weight: 500;
    color: ${palette('text', 0)} !important;
    opacity: 0;
    ${transition()};
  }

  &:hover {
    background-color: ${palette('grayscale', 3)};

    .isoItemRemove {
      opacity: 1;
    }
  }
`;

export default WithDirection(TopbarCartWrapper);
