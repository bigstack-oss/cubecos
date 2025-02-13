// dashboard/containers/storage-widget.js

import { connect } from 'react-redux';

import * as c from '../constant';
import { fetchStorageUsage } from '../action';

import StorageWidget from '../components/storage-widget';

const mapStateToProps = (state, ownProps) => {
  return {
    usage: state[c.NAME].storageUsage,
  };
};

export default connect(mapStateToProps, { fetchStorageUsage })(StorageWidget);