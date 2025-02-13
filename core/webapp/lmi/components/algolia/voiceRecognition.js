import React, { Component } from 'react';
import { PropTypes } from 'prop-types';
import SpeechRecognition from 'react-speech-recognition';
import { VoiceSearchWrapper } from './algoliaComponent.style';

const propTypes = {
  transcript: PropTypes.string,
  resetTranscript: PropTypes.func,
  browserSupportsSpeechRecognition: PropTypes.bool,
};
const options = {
  autoStart: false,
};
class VoiceRecognition extends Component {
  state = {
    listening: false,
  };
  render() {
    const {
      transcript,
      resetTranscript,
      browserSupportsSpeechRecognition,
      startListening,
      stopListening,
      setVoice,
    } = this.props;
    if (!browserSupportsSpeechRecognition) {
      return <div />;
    }
    return (
      <VoiceSearchWrapper className="isoVoiceSearch">
        {!this.state.listening ? (
          <div className="isoVoiceSearchStart">
            <button
              onClick={() => {
                startListening();
                this.setState({ listening: true });
              }}
            />
            <span>Start Speaking</span>
          </div>
        ) : (
          <div className="isoVoiceSearchRunning">
            <button
              onClick={() => {
                setVoice(transcript);
                resetTranscript();
                stopListening();
                this.setState({ listening: false });
              }}
            />
            {/* <span>Search</span> */}
            <span>{transcript}</span>
          </div>
        )}
      </VoiceSearchWrapper>
    );
  }
}
VoiceRecognition.propTypes = propTypes;
export default SpeechRecognition(options)(VoiceRecognition);
