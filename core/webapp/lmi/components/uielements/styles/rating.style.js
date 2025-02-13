import styled from 'styled-components';

const Ratings = ComponentName => styled(ComponentName)`
  .ant-rate-star {
    margin: ${props =>
      props['data-rtl'] === 'rtl' ? '0 0 0 8px' : '0 8px 0 0'};
  }

  .ant-rate-star-first {
    left: ${props => (props['data-rtl'] === 'rtl' ? 'inherit' : '0')};
    right: ${props => (props['data-rtl'] === 'rtl' ? '0' : 'inherit')};
  }
`;

export default Ratings;
