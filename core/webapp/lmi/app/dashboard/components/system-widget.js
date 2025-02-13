// dashboard/components/system-widget.js

import React from 'react';
import ReactPlaceholder from 'react-placeholder';
import createReactClass from 'create-react-class';

import IntlMessages from '../../../components/utility/intlMessages';

import { SystemPartitionDiv, SystemWidgetDiv } from './system-widget-style'

const icon = '/static/image/icon_drive.png';

const SystemPartition = ({ label, type, bootTime, state, boot, checkIcon }) => {
  return (
    <SystemPartitionDiv className={state}>
      <ReactPlaceholder showLoadingAnimation={true} rows={2} type='text' ready={label != ''} color='#E0E0E0'>
        <div className={'partitionImage'}>
          <img src={icon} alt={label}/>
        </div>
        <div className="partitionTitle">
          <h3 className="partitionLabel">{label}</h3>
          <p className="partitionState">{type}</p>
        </div>
        <div className="partitionDetails">
          <span><IntlMessages id={'widget.systemPart.lastBoot'} /></span>
          <span>{bootTime}</span>
        </div>
        <div className="partitionStateIcon">
          <span className={checkIcon}></span>
        </div>
      </ReactPlaceholder>
    </SystemPartitionDiv>
  );
}

const SystemWidget = createReactClass({
  getInitialState: function() {
    return { initial: true };
  },

  componentDidMount: function() {
    this.setState({ initial: true })
  },

  componentWillUnmount: function() {
    this.setState({ initial: true })
  },

  render: function() {
    const { p, fetchPartition } = this.props;

    if (this.state.initial) {
      fetchPartition();
      this.setState({ initial: false })
    }

    return (
      <SystemWidgetDiv>
        <SystemPartition
          label={p.parts[0].version}
          type={p.parts[0].type}
          state={p.active == 1 ? 'active' : 'inactive'}
          bootTime={p.parts[0].boot}
          checkIcon={p.active == 1 ? 'ti-check' : ''}
        />
        <SystemPartition
          label={p.parts[1].version}
          type={p.parts[1].type}
          state={p.active == 2 ? 'active' : 'inactive'}
          bootTime={p.parts[1].boot}
          checkIcon={p.active == 2 ? 'ti-check' : ''}
        />
      </SystemWidgetDiv>
    );
  }
});

export default SystemWidget;
