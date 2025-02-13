import React, { Component } from 'react';
import { connect } from 'react-redux';
import Popover from '../../components/uielements/popover';
import { profile, logout } from '../../app/basic/action';
import TopbarDropdownWrapper from './topbarDropdown.style';

const userpic = '/static/image/user1.png';

class TopbarUser extends Component {
  constructor(props) {
    super(props);
    this.handleVisibleChange = this.handleVisibleChange.bind(this);
    this.hide = this.hide.bind(this);
    this.state = {
      visible: false
    };
  }
  hide() {
    this.setState({ visible: false });
  }
  handleVisibleChange() {
    this.setState({ visible: !this.state.visible });
  }

  render() {
    const content = (
      <TopbarDropdownWrapper className="isoUserDropdown">
        <a className="isoDropdownLink" onClick={this.props.logout}>
          Logout
        </a>
      </TopbarDropdownWrapper>
    );

    if (!this.props.userInfo.username) {
      this.props.profile();
    }

    return (
      <Popover
        content={content}
        trigger="click"
        visible={this.state.visible}
        onVisibleChange={this.handleVisibleChange}
        arrowPointAtCenter={true}
        placement="bottomLeft"
      >
        <div className="isoImgWrapper">
          {this.props.userInfo.username}
        </div>
      </Popover>
    );
  }
}

const mapStateToProps = (state, ownProps) => {
  return {
    userInfo: state['basic'].userInfo,
  };
};

export default connect(mapStateToProps, { profile, logout })(TopbarUser);
