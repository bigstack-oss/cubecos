// dashboard/containers/dashboard.js

import { connect } from 'react-redux';

import Dashboard from '../components/dashboard';

export default connect(state => state)(Dashboard);