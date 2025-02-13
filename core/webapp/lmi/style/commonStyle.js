import styled from 'styled-components';
import { font, palette } from 'styled-theme';

const AppHolder = styled.div`
  ::selection {
    background: ${palette('primary', 0)};
    color: #fff;
  }

  h1,
  h2,
  h3,
  h4,
  h5,
  h6,
  a,
  p,
  li,
  input,
  textarea,
  span,
  div {
    -webkit-font-smoothing: antialiased;
    -moz-osx-font-smoothing: grayscale;
    text-shadow: 1px 1px 1px rgba(0, 0, 0, 0.004);
  }

  html,
  html a {
    -webkit-font-smoothing: antialiased;
    -moz-osx-font-smoothing: grayscale;
    text-shadow: 1px 1px 1px rgba(0, 0, 0, 0.004);
  }

  body {
    font-family: ${font('primary')};
  }
`;

export default AppHolder;
