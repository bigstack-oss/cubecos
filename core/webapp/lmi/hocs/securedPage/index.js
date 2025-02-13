import { compose } from 'redux';

import { withReduxSaga } from '../../app/store';
import WithData from './withData';
import WithLayout from './withLayout';
import WithLang from '../withLang';

export default compose(withReduxSaga, WithData, WithLayout, WithLang);
