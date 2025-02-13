import React, { Component } from 'react';
import Loader from '../utility/loader';
import HelperText from '../utility/helper-text';
import Button from '../uielements/button';
import PlayYoutubeVideo from './playYoutubeVideo';
import {
  YoutubeSearchListStyleWrapper,
  YoutubeSearchStyleWrapper
} from './youtubeSearch.style';

function SearchList(result, handleSelectedVideo) {
  return (
    <YoutubeSearchListStyleWrapper className="isoYoutubeResultList">
      {result.map(item => {
        const {
          publishedAt,
          title,
          description,
          channelTitle,
          thumbnails,
          channelId
        } = item.snippet;
        const id = item.id.videoId;
        const updateDate = new Date(publishedAt).toDateString();
        const onClick = event => {
          event.preventDefault();
          handleSelectedVideo(item);
        };
        const onChannelClick = event => {
          event.preventDefault();
          event.stopPropagation();
          window.open(`https://www.youtube.com/channel/${channelId}`, '_blank');
        };
        return (
          <div key={id} className="isoSingleVideoResult" onClick={onClick}>
            <div className="videoThumb">
              <img alt="#" src={thumbnails.default.url} />
            </div>

            <div className="videoDescription">
              <h3 className="videoName">
                <a href="#">{`${title} `}</a>
              </h3>

              <div className="ChannelNameAndDate">
                <a href="#" onClick={onChannelClick} className="channelTitle">
                  {`${channelTitle} `}
                </a>
                <span className="uploadDate">{updateDate}</span>
              </div>

              {description ? <p>{description}</p> : ''}
            </div>
          </div>
        );
      })}
    </YoutubeSearchListStyleWrapper>
  );
}
export default class extends Component {
  state = {
    selectedVideo: null
  };
  handleCancel = () => {
    this.handleSelectedVideo(null);
  };
  handleSelectedVideo = selectedVideo => {
    this.setState({ selectedVideo });
  };
  render() {
    const { YoutubeSearch, onPageChange } = this.props;
    const { selectedVideo } = this.state;
    const {
      searcText,
      result,
      loading,
      error,
      nextPageToken,
      prevPageToken,
      total_count
    } = YoutubeSearch;
    if (!searcText) {
      return <div />;
    }
    if (loading) {
      return <Loader />;
    }
    if (error || !total_count) {
      return <HelperText text="THERE ARE SOME ERRORS" />;
    }
    if (result.length === 0) {
      return <HelperText text="No Result Found" />;
    }
    return (
      <YoutubeSearchStyleWrapper className="isoYoutubeSearchResult">
        <p className="isoTotalResultFind">
          <span>{`${total_count}`} videos found</span>
        </p>
        {selectedVideo ? (
          <PlayYoutubeVideo
            selectedVideo={this.state.selectedVideo}
            handleCancel={this.handleCancel}
          />
        ) : (
          ''
        )}
        {SearchList(result, this.handleSelectedVideo)}

        <div className="youtubeSearchPagination">
          {prevPageToken ? (
            <Button onClick={() => onPageChange(searcText, prevPageToken)}>
              Previous
            </Button>
          ) : (
            ''
          )}
          {nextPageToken ? (
            <Button onClick={() => onPageChange(searcText, nextPageToken)}>
              Next
            </Button>
          ) : (
            ''
          )}
        </div>
      </YoutubeSearchStyleWrapper>
    );
  }
}
