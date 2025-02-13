import React, { Component } from 'react';
import YouTube from 'react-youtube';
import DefaultModal from '../feedback/modal';
import { YoutubeModal } from './youtubeSearch.style';

const Modal = YoutubeModal(DefaultModal);

export default class extends Component {
  render() {
    const { selectedVideo, handleCancel } = this.props;
    const ops = { playerVars: { autoplay: 1 } };
    return (
      <Modal
        title={selectedVideo.snippet.tittle}
        visible={true}
        footer={null}
        onCancel={handleCancel}
        cancelText="Cancel"
        className="youtubeVideoModal"
        width="670px"
      >
        <div className="isoCardWrapper" />
        <YouTube videoId={selectedVideo.id.videoId} opts={ops} />
      </Modal>
    );
  }
}
