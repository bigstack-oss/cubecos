import React, { Component } from 'react';
import Async from '../../helpers/asyncComponent';
import Button from '../uielements/button';
import Input from '../uielements/input';
import ComposeAutoComplete from './composeAutoComplete';
import notification from '../notification';
import IntlMessages from '../utility/intlMessages';
import ComposeForm from './composeMail.style';

const Editor = props => (
  <Async
    load={import(/* webpackChunkName: "compose-mAIL--editor" */ '../uielements/editor')}
    componentProps={props}
  />
);

function uploadCallback(file) {
  return new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    xhr.open('POST', 'https://api.imgur.com/3/image');
    xhr.setRequestHeader('Authorization', 'Client-ID 8d26ccd12712fca');
    const data = new FormData();
    data.append('image', file);
    xhr.send(data);
    xhr.addEventListener('load', () => {
      const response = JSON.parse(xhr.responseText);
      resolve(response);
    });
    xhr.addEventListener('error', () => {
      const error = JSON.parse(xhr.responseText);
      reject(error);
    });
  });
}
export default class extends Component {
  constructor(props) {
    super(props);
    this.state = {
      editorState: null,
      loading: false,
      iconLoading: false
    };
  }
  render() {
    const onEditorStateChange = editorState => {
      this.setState({ editorState });
    };
    const ComposeAutoCompleteTO = {
      allMails: this.props.allMails,
      updateData: () => {},
      placeholder: 'To'
    };
    const ComposeAutoCompleteCC = {
      allMails: this.props.allMails,
      updateData: () => {},
      placeholder: 'CC'
    };
    const editorOption = {
      style: { width: '90%', height: '70%' },
      editorState: this.state.editorState,
      toolbarClassName: 'home-toolbar',
      wrapperClassName: 'home-wrapper',
      editorClassName: 'home-editor',
      onEditorStateChange: onEditorStateChange,
      uploadCallback: uploadCallback,
      toolbar: { image: { uploadCallback: uploadCallback } }
    };

    return (
      <ComposeForm className="isoComposeMailWrapper">
        <ComposeAutoComplete {...ComposeAutoCompleteTO} />
        <ComposeAutoComplete {...ComposeAutoCompleteCC} />
        <Input placeholder="Subject" className="isoInputBox" />
        <Editor {...editorOption} />
        <div className="isoComposeMailBtnWrapper">
          {this.props.mobileView ? (
            <Button
              type="primary"
              onClick={() => {
                this.props.changeComposeMail(false);
              }}
              className="isoCancelMailBtn"
            >
              <IntlMessages id="email.cancel" />
            </Button>
          ) : (
            ''
          )}

          <Button
            type="primary"
            onClick={e => notification('success', `Mail has been sent`, '')}
            className="isoSendMailBtn"
          >
            <IntlMessages id="email.send" />
          </Button>
        </div>
      </ComposeForm>
    );
  }
}
