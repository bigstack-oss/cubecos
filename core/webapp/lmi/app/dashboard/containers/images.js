// dashboard/containers/images.js

import { connect } from 'react-redux';

import * as c from '../constant';

import Images from '../components/images';

import { fetchImages } from '../action';

const mapStateToProps = (state, ownProps) => {
  return {
    images: state[c.NAME].images,
    groups: state['basic'].userInfo.groups.toString().split(","),
    role: state['basic'].userInfo.role,
  };
};

export default connect(mapStateToProps, { fetchImages })(Images);