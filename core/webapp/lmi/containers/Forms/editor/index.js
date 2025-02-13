import React, { Component } from 'react';
import Async from '../../../helpers/asyncComponent';
import PageHeader from '../../../components/utility/pageHeader';
import Box from '../../../components/utility/box';
import LayoutWrapper from '../../../components/utility/layoutWrapper';
import ContentHolder from '../../../components/utility/contentHolder';
import IntlMessages from '../../../components/utility/intlMessages';

const Editor = props => (
  <Async
    load={import(/* webpackChunkName: "forms-editor" */ '../../../components/uielements/editor')}
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
      <LayoutWrapper>
        <PageHeader>{<IntlMessages id="forms.editor.header" />}</PageHeader>
        <Box>
          <ContentHolder>
            <Editor {...editorOption} />
          </ContentHolder>
        </Box>
      </LayoutWrapper>
    );
  }
}
