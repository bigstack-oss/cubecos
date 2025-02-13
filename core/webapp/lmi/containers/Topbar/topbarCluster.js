import React, { Component } from 'react';
import { connect } from 'react-redux';
import { Icon } from 'antd';
import Dropdown, { DropdownMenu, MenuItem } from '../../components/uielements/dropdown';
import Buttons from '../../components/uielements/button';

const Button = Buttons;

import basic from '../../app/basic';
const selectCluster = basic.action.selectCluster;

class TopbarCluster extends Component {
  constructor(props) {
    super(props);
  }

  render() {
    const { selectCluster, selectedCluster } = this.props;

    let cluster = {};
    let localcluster = {};
    let localname = 'local';
    for (const [n, c] of Object.entries(window.cluster)) {
      if (c.LOCAL) {
        localname = n;
        localcluster = { API_URL: c.API_URL, CUBE_URL: c.CUBE_URL, LOCAL: true };
      }
      else {
        cluster[n] = c;
      }
    }
    cluster[localname] = localcluster;

    if (!selectedCluster) {
      // react app state empty: could be first time login
      window.env.CLUSTER = localname;
    }
    else if (!cluster[selectedCluster]) {
      // reload after cluster.lst imported. selectedCluster leads to undefined cluster info
      window.env.CLUSTER = localname;
      selectCluster({ key: localname });
    }
    else {
      if (window.env.CLUSTER != selectedCluster) {
        if (window.env.CLUSTER) {
          // when click dropdown item
          window.location.reload();
        }
        else {
          // after window.location.reload()
          window.env.CLUSTER = selectedCluster;
        }
      }
    }

    const menuClicked = (
      <DropdownMenu onClick={selectCluster}>
        { Object.keys(cluster).map((t,k) => <MenuItem key={t}>{`${t}: ${cluster[t].CUBE_URL}`} {cluster[t].LOCAL ? '(local)' : ''}</MenuItem>) }
      </DropdownMenu>
    );

    return (
      <Dropdown overlay={menuClicked} trigger={['click']}>
        <Button>
          {`${window.env.CLUSTER}: ${cluster[window.env.CLUSTER].CUBE_URL}`} {cluster[window.env.CLUSTER].LOCAL ? '(local)' : ''} <Icon type="down" />
        </Button>
      </Dropdown>
    );
  }
}

const mapStateToProps = (state, ownProps) => {
  return {
    selectedCluster: state['basic'].selectedCluster,
  };
};

export default connect(mapStateToProps, { selectCluster })(TopbarCluster);
