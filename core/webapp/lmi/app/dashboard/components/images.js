// dashboard/components/images.js

import React from 'react';
import clone from 'clone';
import createReactClass from 'create-react-class';

import * as c from '../constant';

import PageHeader from '../../../components/utility/pageHeader';
import IntlMessages from '../../../components/utility/intlMessages';
import LayoutWrapper from '../../../components/utility/layoutWrapper';
import Tabs, { TabPane } from '../../../components/uielements/tabs';
import Table from '../../../components/uielements/table';

import ImagesDiv from './images-style';

import { notification, Form, Select, Input, Upload, Button, Popconfirm } from 'antd';

const { Option } = Select;

const UploadProps = {
  maxCount: 1,
  name: 'file',
  headers: {
    authorization: 'authorization-text',
  },
  showUploadList: {
    showDownloadIcon: false,
    showRemoveIcon: false,
    showPreviewIcon: false,
  },
};

const ReadableSize = (bytes) => {
  var i = -1;
  var byteUnits = [' kB', ' MB', ' GB', ' TB', 'PB', 'EB', 'ZB', 'YB'];
  if (!bytes || bytes == 0)
    return 'Wait for Importing'

  do {
    bytes = bytes / 1024;
    i++;
  } while (bytes > 1024);

  return Math.max(bytes, 0.1).toFixed(1) + byteUnits[i];
};

const ImagesTable = ({ columns, dataSource }) => {
  return (
    <Table
      rowKey='mid'
      size='small'
      pagination={{ pageSize: 50, position: 'bottom' }}
      columns={columns}
      dataSource={dataSource}
      bordered
    />
  );
};

const Images = createReactClass({
  getInitialState: function() {
    return { refresh: true, actLink: '' };
  },

  componentDidMount: function() {
    this.interval = setInterval(() => this.setState({ refresh: true }), c.MIN_REFRESH);
  },

  componentWillUnmount: function() {
    clearInterval(this.interval);
  },

  renderTable: function(info, dataList) {
    return <ImagesTable columns={info.columns} dataSource={dataList} />;
  },

  render: function() {
    const { images, groups, role, fetchImages } = this.props;

    const { validateFields, getFieldDecorator } = this.props.form;

    const onFormSubmit = e => {
      e.preventDefault();
      return validateFields((err, values) => {
        if (!err)
          this.setState({ actLink: `/v1/manage/images?project=${values.project}&name=${values.name}`});
      });
    };

    const beforeUpload = file => {
      let check = true;
      validateFields((err, values) => {
        if (err) {
          notification['error']({
            message: 'Importing Image',
            description: 'Project and image name are required',
          });
          check = false;
        }
      });
      const isLt100G = file.size / 1024 / 1024 / 1024 < 100;
      if (!isLt100G) {
        notification['error']({
          message: 'Importing Image',
          description: `Image ${file.name} is larger than 100GB!`,
        });
      }
      return check && isLt100G;
    };

    const onUploadChange = info => {
      if (info.file.status === 'done') {
        const key = `open${Date.now()}`;
        const btn = (
          <Button type="primary" size="small" onClick={() => notification.close(key)}>
            Confirm
          </Button>
        );
        notification['success']({
          message: 'Importing Image',
          description: `Image ${info.file.name} is successfully uploaded. It will take a while for fully imported. You can come back later or wait for auto refresh.`,
          btn,
          key,
          duration: 0,
        });
        this.setState({ refresh: true });
      } else if (info.file.status === 'error') {
        notification['error']({
          message: 'Importing Image',
          description: `Image ${info.file.name} failed to imported`,
        });
      }
    };

    const onDeleteImg = obj => {
      fetch(`${window.cluster[window.env.CLUSTER].API_URL}/v1/manage/images/` + obj['ID'], {
        method: 'DELETE',
      })
      .then((res) => {
        if (!res.ok) {
          throw new Error(res.statusText);
        }
        notification['success']({
          message: 'Deleting Image',
          description: `Image ${obj['Name']} is successfully deleted.`,
        });
      })
      .catch((err) => {
        notification['error']({
          message: 'Deleting Image',
          description: `Failed to delete image ${obj['Name']}, reason: ${err.message}.`,
        });
      });
    };

    const columns = [
      {
        title: <IntlMessages id="images.name" />,
        key: 'Name',
        width: '35%',
        render: object => (<span>{object['Name']}</span>)
      },
      {
        title: <IntlMessages id="images.format" />,
        key: 'Disk Format',
        width: '15%',
        render: object => (<span>{object['Disk Format']}</span>)
      },
      {
        title: <IntlMessages id="images.size" />,
        key: 'Size',
        width: '15%',
        render: object => (<span>{ReadableSize(object['Size'])}</span>)
      },
      {
        title: <IntlMessages id="images.visibility" />,
        key: 'Visibility',
        width: '15%',
        render: object => (<span>{object['Visibility']}</span>)
      },
      {
        title: <IntlMessages id="images.action" />,
        key: 'ID',
        width: '30%',
        render: object => (
          <Popconfirm title={`Remove image ${object['Name']}?`} okText="Yes" cancelText="No" onConfirm={() => { onDeleteImg(object); fetchImages(); }} >
            <a>Delete</a>
          </Popconfirm>
        )
      },
    ];

    if (this.state.refresh) {
      fetchImages();
      this.setState({ refresh: false });
    }

    let tableTabs = []
    let projs = []
    if (role == 'admin') {
      for (var p in images){
        if (p != 'service')
          projs.push(p)
        if (images[p].length > 0)
          tableTabs.push({title: p, value: p, columns: columns})
      }
    }
    else {
      for (var i = 0 ; i < groups.length ; i++) {
        let gname = groups[i];
        let gitems = groups[i].split("-");
        if (gitems.length > 1) {
          const r = gitems[gitems.length - 1]
          if (r == 'creator' || r == 'admin' || r == 'member') {
            gitems.pop();
            gname = gitems.join("-")
          }
        }
        if (gname != 'cube-users')
          projs.push(gname)
        if (images && images[gname] && images[gname].length > 0)
          tableTabs.push({title: gname, value: gname, columns: columns})
      }
    }

    return (
      <LayoutWrapper>
        {/*<PageHeader>{<IntlMessages id="page.images" />}</PageHeader>*/}
        <ImagesDiv className="isoLayoutContent">
          <Tabs className="isoTableDisplayTab">
            {tableTabs.length > 0 && tableTabs.map(info => (
              <TabPane tab={info.title} key={info.value}>
                {this.renderTable(info, images[info.value])}
              </TabPane>
            ))}
          </Tabs>
          <Form layout="inline" onSubmit={onFormSubmit}>
            <Form.Item name="project">
              {getFieldDecorator('project', {
                rules: [{ required: true, message: 'Please select a project!' }],
              })(
                <Select style={{ width: '150px' }} placeholder="Project">
                  {projs.length > 0 && projs.map(proj => (
                    <Option value={proj}>{proj}</Option>
                  ))}
                </Select>
              )}
            </Form.Item>
            <Form.Item name="name">
              {getFieldDecorator('name', {
                rules: [{ required: true, message: 'Please input image name!' }],
              })(
                <Input style={{ width: '150px' }} placeholder='Image Name' />
              )}
            </Form.Item>
            <Form.Item>
              <Upload {...UploadProps} action={this.state.actLink} onChange={onUploadChange} beforeUpload={beforeUpload}>
                <Button type='primary' htmlType='submit'>+ Upload Image</Button>
              </Upload>
            </Form.Item>
          </Form>
        </ImagesDiv>
      </LayoutWrapper>
    );
  }
});

export default Form.create()(Images);