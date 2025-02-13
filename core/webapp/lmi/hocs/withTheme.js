import { ThemeProvider } from 'styled-components';
import theme from '../config/theme';

export default ComposedComponent => props => (
  <ThemeProvider theme={theme}>
    <ComposedComponent {...props} />
  </ThemeProvider>
);
