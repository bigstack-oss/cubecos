import React, { Component } from 'react';
import { Icon } from 'antd';
import Modal from '../../../components/feedback/modal';
import Upload from '../../../components/uielements/upload';
import PageHeader from '../../../components/utility/pageHeader';
import Box from '../../../components/utility/box';
import LayoutWrapper from '../../../components/utility/layoutWrapper';
import ContentHolder from '../../../components/utility/contentHolder';

export default class extends Component {
  state = {
    previewVisible: false,
    previewImage: '',
    fileList: [
      {
        uid: -1,
        name: 'xxx.png',
        status: 'done',
        url:
          'https://zos.alipayobjects.com/rmsportal/jkjgkEfvpUPVyRjUImniVslZfWPnJuuZ.png'
      }
    ]
  };

  handleCancel = () => this.setState({ previewVisible: false });

  handlePreview = file => {
    this.setState({
      previewImage: file.url || file.thumbUrl,
      previewVisible: true
    });
  };

  handleChange = ({ fileList }) => this.setState({ fileList });

  render() {
    const { previewVisible, previewImage, fileList } = this.state;
    const uploadButton = (
      <div className="isoUploadBtn">
        <Icon type="plus" />
        <span className="isoUploadText">Upload</span>
      </div>
    );
    return (
      <LayoutWrapper>
        <PageHeader>Upload</PageHeader>

        <Box
          title="Search"
          subtitle="You could pass AutoComplete.Option as children of AutoComplete, instead of using dataSource"
        >
          <ContentHolder>
            <Upload
              action="//jsonplaceholder.typicode.com/posts/"
              listType="picture-card"
              fileList={fileList}
              onPreview={this.handlePreview}
              onChange={this.handleChange}
            >
              {fileList.length >= 3 ? null : uploadButton}
            </Upload>
            <Modal
              visible={previewVisible}
              footer={null}
              onCancel={this.handleCancel}
            >
              <img alt="example" style={{ width: '100%' }} src={previewImage} />
            </Modal>
          </ContentHolder>
        </Box>
      </LayoutWrapper>
    );
  }
}
