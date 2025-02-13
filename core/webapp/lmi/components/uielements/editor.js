import React, { Component } from 'react';
import ReactQuill from 'react-quill';
import quillSnowCss from 'react-quill/dist/quill.snow.css';
import quillCoreCss from 'react-quill/dist/quill.core.css';
import QuillEditor from './styles/editor.style';

const quillModules = {
  toolbar: {
    container: [
      [{ header: [1, 2, false] }, { font: [] }],
      ['bold', 'italic', 'underline', 'strike', 'blockquote'],
      [
        { list: 'ordered' },
        { list: 'bullet' },
        { indent: '-1' },
        { indent: '+1' }
      ],
      ['link', 'image', 'video'],
      ['clean']
    ]
  }
};
export default class Editor extends Component {
  state = { value: '' };
  handleChange = value => {
    this.setState({ value });
  };
  render() {
    const options = {
      theme: 'snow',
      formats: Editor.formats,
      placeholder: 'Write Something',
      value: this.state.value,
      onChange: this.handleChange,
      modules: quillModules
    };
    return (
      <div>
        <style>{quillSnowCss}</style>
        <style>{quillCoreCss}</style>
        <QuillEditor>
          <ReactQuill {...options} />
        </QuillEditor>
      </div>
    );
  }
}
